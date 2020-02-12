FROM golang:1.13-stretch

maintainer "worksg <null@example.com>"

ENV SRC_DIR /go-ipfs

ARG IPFS_VERSION

RUN curl -L https://github.com/ipfs/go-ipfs/releases/download/${IPFS_VERSION}/go-ipfs_${IPFS_VERSION}_linux-amd64.tar.gz \
    -o /go-ipfs_${IPFS_VERSION}_linux-amd64.tar.gz \
    && tar zxf /go-ipfs_${IPFS_VERSION}_linux-amd64.tar.gz -C / \
    && rm -f /go-ipfs_${IPFS_VERSION}_linux-amd64.tar.gz

# Get su-exec, a very minimal tool for dropping privileges,
# and tini, a very minimal init daemon for containers
ENV SUEXEC_VERSION v0.2
ENV TINI_VERSION v0.16.1
RUN set -x \
    && cd /tmp \
    && git clone https://github.com/ncopa/su-exec.git \
    && cd su-exec \
    && git checkout -q $SUEXEC_VERSION \
    && make \
    && cd /tmp \
    && wget -q -O tini https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini \
    && chmod +x tini

# Get the TLS CA certificates, they're not provided by busybox.
RUN apt-get update && apt-get install -y ca-certificates

# Now comes the actual target image, which aims to be as small as possible.
FROM frolvlad/alpine-glibc:alpine-3.10

ENV SRC_DIR /go-ipfs
COPY --from=0 $SRC_DIR/ipfs /usr/local/bin/ipfs
COPY --from=0 /tmp/su-exec/su-exec /sbin/su-exec
COPY --from=0 /tmp/tini /sbin/tini
COPY --from=0 /etc/ssl/certs /etc/ssl/certs

COPY container_daemon /usr/local/bin/start_ipfs
RUN chmod +x /usr/local/bin/start_ipfs

LABEL maintainer "worksg <null@example.com>"

# This shared lib (part of glibc) doesn't seem to be included with busybox.
# COPY --from=0 /lib/x86_64-linux-gnu/libdl-2.24.so /lib/libdl.so.2

ARG TZ='UTC'

# Swarm TCP; should be exposed to the public
EXPOSE 4001
# Daemon API; must not be exposed publicly but to client services under you control
EXPOSE 5001
# Web Gateway; can be exposed publicly with a proxy, e.g. as https://ipfs.example.org
EXPOSE 8080
# Swarm Websockets; must be exposed publicly when the node is listening using the websocket transport (/ipX/.../tcp/8081/ws).
EXPOSE 8081

# Create the fs-repo directory and switch to a non-privileged user.
ENV IPFS_PATH /data/ipfs
RUN mkdir -p $IPFS_PATH \
    && adduser -D -h $IPFS_PATH -u 1000 -G users ipfs \
    && chown ipfs:users $IPFS_PATH

# private network swarm key
COPY ipfs-swarm.key /data/ipfs/swarm.key

# Expose the fs-repo as a volume.
# start_ipfs initializes an fs-repo if none is mounted.
# Important this happens after the USER directive so permission are correct.
# 文件夹权限在start_ipfs被重写，避免ipfs用户的读写权限问题
VOLUME $IPFS_PATH

# The default logging level
ENV IPFS_LOGGING ""

# This just makes sure that:
# 1. There's an fs-repo, and initializes one if there isn't.
# 2. The API and Gateway are accessible from outside the container.
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/start_ipfs"]

# Execute the daemon subcommand by default
CMD ["daemon", "--migrate=true"]
