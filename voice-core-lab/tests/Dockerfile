FROM debian:bookworm-slim

# sip-tester is the Debian package name for SIPp.
RUN apt-get update \
    && apt-get install -y --no-install-recommends sip-tester ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY scenarios /scenarios
COPY run_tests.sh /run_tests.sh
RUN chmod +x /run_tests.sh

CMD ["/run_tests.sh"]
