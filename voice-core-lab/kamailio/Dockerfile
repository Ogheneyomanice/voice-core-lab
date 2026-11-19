FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends kamailio ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY kamailio.cfg /etc/kamailio/kamailio.cfg

# Module test: the image build fails here if the configuration has a syntax error.
RUN kamailio -c -f /etc/kamailio/kamailio.cfg

EXPOSE 5060/udp 5060/tcp

CMD ["kamailio", "-DD", "-E", "-f", "/etc/kamailio/kamailio.cfg"]
