#!/bin/bash

# wget -N https://huggingface.co/jgkawell/jarvis/resolve/main/en/en_GB/jarvis/high/jarvis-high.onnx
# wget -N https://huggingface.co/jgkawell/jarvis/resolve/main/en/en_GB/jarvis/high/jarvis-high.onnx.json

wget -N https://huggingface.co/jgkawell/jarvis/resolve/main/en/en_GB/jarvis/medium/jarvis-medium.onnx
wget -N https://huggingface.co/jgkawell/jarvis/resolve/main/en/en_GB/jarvis/medium/jarvis-medium.onnx.json

python convert.py

wget -N https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/espeak-ng-data.tar.bz2
tar xf espeak-ng-data.tar.bz2
rm espeak-ng-data.tar.bz2