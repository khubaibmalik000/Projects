FROM postgres:16
COPY slave-entrypoint.sh /usr/local/bin/slave-entrypoint.sh
RUN chmod +x /usr/local/bin/slave-entrypoint.sh
ENTRYPOINT ["slave-entrypoint.sh"]
CMD ["postgres"]
