FROM scratch
COPY --chown=10001:10001 dist/calculator /calculator
COPY --chown=10001:10001 dist/data/ /data/
USER 10001:10001
ENV DB_PATH=/data/calculator.db LISTEN_ADDR=:8080
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=4s --start-period=10s --retries=3 CMD ["/calculator", "healthcheck"]
ENTRYPOINT ["/calculator"]
