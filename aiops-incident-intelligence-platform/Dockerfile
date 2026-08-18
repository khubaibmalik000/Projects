FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

FROM base AS builder
COPY pyproject.toml ./
COPY src ./src
COPY README.md ./
RUN pip install --upgrade pip && pip install --prefix=/install .

FROM base AS runtime
RUN useradd --create-home --uid 10001 aiops
COPY --from=builder /install /usr/local
COPY src ./src
COPY scripts ./scripts
ENV AIOPS_DATABASE_URL=sqlite:////data/aiops.db
RUN mkdir -p /data && chown aiops:aiops /data
USER aiops
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/v1/health', timeout=2).status == 200 else 1)"

CMD ["uvicorn", "aiops.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
