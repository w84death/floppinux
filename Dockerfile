FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    vim \
    git \
    wget \
    rsync \
    curl \
    time \
    unzip \
    zip \
    flex \
    bison \
    bc \
    libncurses-dev \
    libcrypt-dev \
    cpio \
    dosfstools \
    syslinux

WORKDIR /src
ADD . /src

CMD [ "make", "all" ]