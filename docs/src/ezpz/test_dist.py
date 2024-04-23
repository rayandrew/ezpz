"""
ezpz_ddp.py

- to launch:

  $ source ezpz/src/ezpz/bin/savejobenv
  $ BACKEND=DDP launch python3 ezpz_ddp.py
"""
import os
import logging
import time
from typing import Optional
import torch
import ezpz as ez

# backend can be any of DDP, deespepeed, horovod
DIST_INIT = ez.setup_torch_distributed(
    backend=(
        backend := os.environ.get('BACKEND', 'DDP')
    ),
    port=(
        port := os.environ.get("MASTER_PORT", "29500")
    )
)
DEVICE = ez.get_torch_device()
RANK = DIST_INIT['rank']
WORLD_SIZE = DIST_INIT['world_size']
LOCAL_RANK = DIST_INIT['local_rank']
# WORLD_SIZE = ez.get_world_size()
# LOCAL_RANK = ez.get_local_rank()
DEVICE_ID = f"{DEVICE}:{LOCAL_RANK}"
_ = ez.print_dist_setup()

if DEVICE == "cuda" and torch.cuda.is_available():
    torch.cuda.set_device(LOCAL_RANK)

# log only from RANK == 0
logger = logging.getLogger(__name__)
logger.setLevel("INFO") if RANK == 0 else logger.setLevel("CRITICAL")

BATCH_SIZE = 64
INPUT_SIZE = 128
OUTPUT_SIZE = 128
DTYPE = torch.get_default_dtype()

logger.info(f"{DIST_INIT=}")


class Network(torch.nn.Module):
    def __init__(
            self,
            input_dim: int = 128,
            output_dim: int = 128,
            sizes: Optional[list[int]] = None,
    ):
        super(Network, self).__init__()
        if sizes is None:
            self.layers = torch.nn.Linear(input_dim, output_dim)
        elif len(sizes) > 0:
            layers = [torch.nn.Linear(input_dim, sizes[0])]
            for idx, size in enumerate(sizes[1:]):
                layers.append(
                    torch.nn.Linear(sizes[idx], size)
                )
            layers.append(torch.nn.Linear(sizes[-1], output_dim))
            self.layers = torch.nn.Sequential(*layers)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.layers(x)


def calc_loss(x: torch.Tensor, y: torch.Tensor) -> torch.Tensor:
    return (y - x).pow(2).sum()


def main():
    model = Network(
        input_dim=INPUT_SIZE,
        output_dim=OUTPUT_SIZE,
        sizes=[1024, 512, 256, 128]
    )
    model.to(DEVICE)
    model.to(DEVICE_ID)
    logger.info(f'{model=}')
    optimizer = torch.optim.Adam(model.parameters())
    if WORLD_SIZE > 1:
        if backend.lower() == 'ddp':
            from torch.nn.parallel import DistributedDataParallel as DDP
            model = DDP(
                model,
                device_ids=[]
            )
        elif backend.lower() in ('ds', 'deepspeed'):
            import deepspeed
            # config = ez.load_ds_config().update(
            #     {"train_micro_batch_size_per_gpu": BATCH_SIZE}
            # )
            import argparse
            parser = argparse.ArgumentParser(description='My training script.')
            parser.add_argument('--local_rank', required=False, type=int, default=-1,  # default=ez.get_local_rank()),
                                help='local rank passed from distributed launcher')
            # Include DeepSpeed configuration arguments
            parser = deepspeed.add_config_arguments(parser)
            cmd_args = parser.parse_args()
            logger.info(f'{cmd_args=}')
            model, optimizer, *_ = deepspeed.initialize(
                args=cmd_args,
                model=model,
                optimizer=optimizer,
            )

    for iter in range(10):
        t0 = time.perf_counter()
        x = torch.rand((BATCH_SIZE, INPUT_SIZE), dtype=DTYPE).to(DEVICE)
        y = model(x)
        loss = calc_loss(x, y)
        dtf = ((t1 := time.perf_counter()) - t0)
        if backend == 'deepspeed':
            model.backward(loss)
            model.step(loss)
        else:
            loss.backward()
            optimizer.step()
        optimizer.zero_grad()
        dtb = time.perf_counter() - t1
        logger.info(
            ', '.join([
                f'{iter=}',
                f'loss={loss.item():.5f}',
                f'dt={dtf+dtb:.3f}',
                f'{dtf=:.3f}',
                f'{dtb=:.3f}'
            ])
        )


if __name__ == '__main__':
    main()
