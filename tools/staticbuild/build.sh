#!/usr/bin/env bash

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

if [ $# -lt 1 ]; then
    >&2 echo "Usage: build.sh <VARIANT>"
fi

export CURDIR=$PWD
export DEPS_PATH=$PWD/staticdeps
export VARIANT=$(echo $1 | tr '[:upper:]' '[:lower:]')
export PLATFORM=$(uname | tr '[:upper:]' '[:lower:]')

if [[ $VARIANT == darwin* ]]; then
    export VARIANT="darwin"
fi

NUM_PROC=1
if [[ ! -z $(command -v nproc) ]]; then
    NUM_PROC=$(nproc)
elif [[ ! -z $(command -v sysctl) ]]; then
    NUM_PROC=$(sysctl -n hw.ncpu)
else
    >&2 echo "Can't discover number of cores."
fi
export NUM_PROC
>&2 echo "Using $NUM_PROC parallel jobs in building."

if [[ $DEBUG -eq 1 ]]; then
    export ADD_MAKE_FLAG="-j $NUM_PROC"
else
    export ADD_MAKE_FLAG="--quiet -j $NUM_PROC"
fi
export MAKE="make $ADD_MAKE_FLAG"

export CC="gcc -fPIC -mno-avx"
export CXX="g++ -fPIC -mno-avx"
export FC="gfortran"
export PKG_CONFIG_PATH=$DEPS_PATH/lib/pkgconfig:$DEPS_PATH/lib64/pkgconfig:$DEPS_PATH/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH
export CPATH=$DEPS_PATH/include:$CPATH

if [[ $PLATFORM == 'linux' && $VARIANT == cu* ]]; then
    source tools/setup_gpu_build_tools.sh $VARIANT $DEPS_PATH
fi

mkdir -p $DEPS_PATH

# Build Dependencies
source tools/dependencies/make_shared_dependencies.sh

echo $LD_LIBRARY_PATH

echo $CPLUS_INCLUDE_PATH

if [[ $PLATFORM == 'linux' && $VARIANT == cu* ]]; then
    export CC=gcc-7
    export CXX=g++-7
    export ONNX_NAMESPACE=onnx
    export PATH=${PATH}:$DEPS_PATH/protobuf-3.5.1/src
    # Build ONNX
    pushd .
    echo "Installing ONNX."
    cd 3rdparty/onnx-tensorrt/third_party/onnx
    rm -rf build
    mkdir -p build
    cd build
    cmake -DCMAKE_CXX_FLAGS=-I/usr/include/python${PYVER} \
          -DBUILD_SHARED_LIBS=ON \
          -DProtobuf_LIBRARY=$DEPS_PATH/lib/libprotobuf.so \
          ..
    make -j$(nproc)
    export LIBRARY_PATH=`pwd`:`pwd`/onnx/:$LIBRARY_PATH
    export CPLUS_INCLUDE_PATH=`pwd`:$CPLUS_INCLUDE_PATH
    export CXXFLAGS=-I`pwd`

    popd

    # Build ONNX-TensorRT
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/local/lib
    export CPLUS_INCLUDE_PATH=${CPLUS_INCLUDE_PATH}:$DEPS_PATH/include:/usr/local/cuda-11.0/targets/x86_64-linux/include/
    pushd .
    cd 3rdparty/onnx-tensorrt/
    mkdir -p build
    cd build
    cmake -DONNX_NAMESPACE=$ONNX_NAMESPACE -DTENSORRT_INCLUDE_DIR=$DEPS_PATH/usr/include/x86_64-linux-gnu \
        -DTENSORRT_LIBRARY_INFER=$DEPS_PATH/usr/lib/x86_64-linux-gnu \
        -DTENSORRT_LIBRARY_INFER_PLUGIN=$DEPS_PATH/usr/lib/x86_64-linux-gnu \
        -DTENSORRT_LIBRARY_MYELIN=$DEPS_PATH/usr/lib/x86_64-linux-gnu \
        -DProtobuf_INCLUDE_DIR=$DEPS_PATH/include \
        -DProtobuf_LIBRARY=$DEPS_PATH/lib \
        ..
    make -v -j$(nproc)
    export LIBRARY_PATH=`pwd`:$LIBRARY_PATH
    popd

    mkdir -p $DEPS_PATH/usr/{lib,include,onnx}
    cp 3rdparty/onnx-tensorrt/third_party/onnx/build/*.so $DEPS_PATH/usr/lib
    cp -f 3rdparty/onnx-tensorrt/third_party/onnx/{build/,}onnx/*.h $DEPS_PATH/usr/include
fi

# Copy LICENSE
mkdir -p licenses
cp tools/dependencies/LICENSE.binary.dependencies licenses/
cp NOTICE licenses/
cp LICENSE licenses/
cp DISCLAIMER-WIP licenses/
cp AWS_MX_LicenseAgreement.txt python/mxnet/AWS_MX_LicenseAgreement.txt

# Build mxnet
if [[ -z "$CMAKE_STATICBUILD" ]]; then
    source tools/staticbuild/build_lib.sh
else
    source tools/staticbuild/build_lib_cmake.sh
fi
