#!/bin/bash

quickemu --vm ~/vms/archlinux/archlinux-latest.conf --snapshot create "${1:-clean-base}"
