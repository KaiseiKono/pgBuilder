FROM perl:5.38

WORKDIR /app

RUN apt-get update && apt-get install -y \
    default-libmysqlclient-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY cpanfile .
RUN cpanm --installdeps --verbose .

COPY . .
EXPOSE 3000

CMD ["morbo", "-l", "http://0.0.0.0:3000", "myapp.pl"]