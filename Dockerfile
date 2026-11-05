FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && useradd --create-home --uid 10001 fray
COPY --chown=fray:fray web/ ./
COPY --chown=fray:fray scripts/start-web.sh /app/start-web.sh
RUN chmod +x /app/start-web.sh
USER fray
EXPOSE 8000
CMD ["/app/start-web.sh"]
