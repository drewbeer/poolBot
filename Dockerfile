# i know this is crazy, but installing our own perl is just better in the long run.

ARG BASE_ARCH
FROM $BASE_ARCH
MAINTAINER Drew

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Version:- ${VERSION} Build-date:- ${BUILD_DATE}"

RUN apk update && apk upgrade

# install packages
RUN \
 apk add --no-cache \
	curl \
  jq \
  openssl \
  openssl-dev \
  wget \
  tar \
  make \
  gcc \
  build-base \
  gnupg \
  redis \
  zlib-dev \
  zlib \
  docker-cli \
  py-pip \
  python3-dev \
  wiringpi

# build perl
RUN mkdir -p /usr/src/perl

WORKDIR /usr/src/perl

## from perl; `true make test_harness` because 3 tests fail
## some flags from http://git.alpinelinux.org/cgit/aports/tree/main/perl/APKBUILD?id=19b23f225d6e4f25330e13144c7bf6c01e624656
RUN curl -SLO https://cpan.metacpan.org/authors/id/S/SH/SHAY/perl-5.26.2.tar.bz2 \
    && echo '2057b65e3a6ac71287c973402cd01084a1edc35b *perl-5.26.2.tar.bz2' | sha1sum -c - \
    && tar --strip-components=1 -xjf perl-5.26.2.tar.bz2 -C /usr/src/perl \
    && rm perl-5.26.2.tar.bz2 \
    && ./Configure -des \
        -Dcccdlflags='-fPIC' \
        -Dcccdlflags='-fPIC' \
        -Dccdlflags='-rdynamic' \
        -Dlocincpth=' ' \
        -Duselargefiles \
        -Dusethreads \
        -Duseshrplib \
        -Dd_semctl_semun \
        -Dusenm \
    && make libperl.so \
    && make -j$(nproc) \
    && TEST_JOBS=$(nproc) true make test_harness \
    && make install \
    && curl -LO https://raw.githubusercontent.com/miyagawa/cpanminus/master/cpanm \
    && chmod +x cpanm \
    && ./cpanm App::cpanminus \
    && rm -fr ./cpanm /root/.cpanm /usr/src/perl

## from tianon/perl
ENV PERL_CPANM_OPT --verbose --mirror https://cpan.metacpan.org --mirror-only
RUN cpanm Digest::SHA Module::Signature && rm -rf ~/.cpanm

WORKDIR /

RUN echo "***** installing prereq ****" && cpanm -f -v --notest Time::Zone Date::Parse CHI DateTime
ENV PERL_CPANM_OPT $PERL_CPANM_OPT --verify


RUN \
echo "***** install perl modules ****" && \
cpanm --no-wget --notest \
  AnyEvent \
  AnyEvent::Fork \
  FindBin Data::Dumper \
  Log::Log4perl \
  JSON \
  Config::Simple \
  Redis \
  Storable \
  String::Escape \
  IO::Socket \
  HTTP::Tiny \
  Coro \
  EV \
  InfluxDB::LineProtocol \
  AnyEvent::DateTime::Cron \
  AnyEvent::HTTPD \
  Net::MQTT::Simple


  # copy local files
  RUN mkdir /poolBot
  COPY . /poolBot/
  RUN chmod +x /poolBot/bin/poolBot.pl

  EXPOSE 8080

  ENTRYPOINT ["perl", "/poolBot/bin/poolBot.pl"]
