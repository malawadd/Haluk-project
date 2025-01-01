# Miner

## Overview

This repository contains instructions for setting up a Haluk Node—contributing your GPU resources to the Haluk network on opBNB. You’ll run a central controller on a CPU server, managing multiple GPU executors that process AI workflows (e.g., ComfyUI text-to-video tasks). As a Node Provider, you receive $HALUK for maintaining high uptime and delivering compute services.

### Central Miner Server Requirements

To run the central miner, you only need a CPU server with the following specifications:

- **CPU**: 4 cores
- **RAM**: 8GB
- **Storage**: 50GB available disk space
- **OS**: Ubuntu (recommended)

### GPU Executors

- **Purpose**: Perform actual computation.  
- **Managed By**: The central controller, which can add or remove executors as needed.  
- **Compatibility**: NVIDIA GPUs (or others, if supported by your Docker environment).



## Installation

TBD