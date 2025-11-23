FROM python:3.10-bullseye

# Install Java 17 and other dependencies
RUN apt-get update && \
    apt-get install -y \
    openjdk-17-jre-headless \
    curl \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Set Java environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
ENV PATH=$JAVA_HOME/bin:$PATH

# Verify Java installation
RUN java -version

# Install Python packages
RUN pip install --no-cache-dir \
    marimo==0.17.8 \
    pyspark==3.4.1 \
    pandas \
    requests

# Create app directory
WORKDIR /app

# Create notebooks directory
RUN mkdir -p /app/notebooks

# Set environment variables for marimo
ENV MARIMO_SKIP_UPDATE_CHECK=1
ENV MARIMO_DISABLE_AUTH=1

# Set Spark/JVM memory settings
ENV SPARK_DRIVER_MEMORY=1g
ENV SPARK_EXECUTOR_MEMORY=1g
ENV PYSPARK_DRIVER_PYTHON=python3
ENV PYSPARK_PYTHON=python3

# Expose port
EXPOSE 2718

# Default command
CMD ["marimo", "edit", "notebooks/analysis.py", "--host", "0.0.0.0", "--port", "2718", "--no-token"]
