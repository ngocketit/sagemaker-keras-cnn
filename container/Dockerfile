FROM ubuntu:16.04

RUN apt-get update -y && \
	apt-get install -y software-properties-common && \
	apt-get install -y python-software-properties && \
	add-apt-repository ppa:deadsnakes/ppa && \
	apt-get update -y && \
	apt-get install -y --no-install-recommends \
        wget \
        python3.6 \
        nginx \
        ca-certificates \
	libsm6 libxext6 libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Here we get all python packages.
# There's substantial overlap between scipy and numpy that we eliminate by
# linking them together. Likewise, pip leaves the install caches populated which uses
# a significant amount of space. These optimizations save a fair amount of space in the
# image, which reduces start up time.
RUN wget https://bootstrap.pypa.io/get-pip.py && python get-pip.py && \
    pip install pillow jsonpickle numpy===1.14.5 keras tensorflow opencv-python opencv-contrib-python flask gevent gunicorn && \
        rm -rf /root/.cache

# Set some environment variables. PYTHONUNBUFFERED keeps Python from buffering our standard
# output stream, which means that logs can be delivered to the user quickly. PYTHONDONTWRITEBYTECODE
# keeps Python from writing the .pyc files which are unnecessary in this case. We also update
# PATH so that the train and serve programs are found when the container is invoked.

ENV PYTHONUNBUFFERED=TRUE
ENV PYTHONDONTWRITEBYTECODE=TRUE
ENV PATH="/opt/program:${PATH}"

# Set up the program in the image
COPY cnn /opt/program
WORKDIR /opt/program
