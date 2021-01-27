FROM golang:alpine AS go-jsonnet

ENV JSONNET_VERSION v0.17.0
# Waiting for https://github.com/google/go-jsonnet/issues/483 to get into a release
ENV JSONNET_LINTER_VERSION 31d71aaccda6d98135ecc02acae823ef6e78270c
ENV JB_VERSION 0.4.0

RUN apk add --no-cache bash git && \
  mkdir -p /build/bin && \
  cd /build && \
  go mod init local/build && \
  go get -d github.com/google/go-jsonnet/cmd/jsonnet@$JSONNET_VERSION && \
  go build -o /build/bin/jsonnet github.com/google/go-jsonnet/cmd/jsonnet && \
  go get -d github.com/google/go-jsonnet/cmd/jsonnetfmt@$JSONNET_VERSION && \
  go build -o /build/bin/jsonnetfmt github.com/google/go-jsonnet/cmd/jsonnetfmt && \
  go get -d github.com/google/go-jsonnet/cmd/jsonnet-lint@$JSONNET_LINTER_VERSION && \
  go build -o /build/bin/jsonnet-lint github.com/google/go-jsonnet/cmd/jsonnet-lint && \
  go get -d github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@v$JB_VERSION && \
  go build -o /build/bin/jb github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb && \
  rm -rf /tmp/* /var/tmp/* /var/cache/apk/*

FROM google/cloud-sdk:alpine

# Make sure these version numbers are not ahead of whats running in Production
ENV ALERTMANAGER_VERSION 0.21.0
ENV PROMETHEUS_VERSION 2.20.1

RUN apk add --no-cache curl bash git jq alpine-sdk ruby build-base ruby-dev tar gcc libc-dev make
RUN gcloud components install kubectl -q

RUN mkdir /alertmanager && \
  wget -O alertmanager.tar.gz https://github.com/prometheus/alertmanager/releases/download/v$ALERTMANAGER_VERSION/alertmanager-$ALERTMANAGER_VERSION.linux-amd64.tar.gz && \
  tar -xvf alertmanager.tar.gz -C /alertmanager --strip-components 1 --wildcards */amtool && \
  rm alertmanager.tar.gz && \
  ln -s /alertmanager/amtool /bin/amtool

RUN mkdir /prometheus && \
  wget -O prometheus.tar.gz https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz && \
  tar -xvf prometheus.tar.gz -C /prometheus --strip-components 1 --wildcards */promtool && \
  rm prometheus.tar.gz && \
  ln -s /prometheus/promtool /bin/promtool

COPY --from=nlknguyen/alpine-shellcheck:latest /usr/local/bin/shellcheck /usr/local/bin/shellcheck
COPY --from=peterdavehello/shfmt:latest /bin/shfmt /usr/local/bin/shfmt

COPY --from=go-jsonnet /build/bin/jsonnet /bin/jsonnet
COPY --from=go-jsonnet /build/bin/jsonnetfmt /bin/jsonnetfmt
COPY --from=go-jsonnet /build/bin/jsonnet-lint /bin/jsonnet-lint
COPY --from=go-jsonnet /build/bin/jb /bin/jb

RUN gem install --no-document json && \
  gem install --no-document yaml-lint && \
  rm -rf /tmp/* /var/tmp/* /var/cache/apk/*

ENTRYPOINT ["/bin/sh", "-c"]
