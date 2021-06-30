# -------------------------------------------------------------------
# Minimal dockerfile from alpine base
#
# Instructions :
# =============
# 1. Create an empty directory and copy this file into it.
#
# 2. Create image with: 
#	docker build --tag timeoff:latest .
#
# 3. Run with: 
#	docker run -d -p 3000:3000 --name alpine_timeoff timeoff
#
# 4. Login to running container (to update config (vi config/app.json): 
#	docker exec -ti --user root alpine_timeoff /bin/sh
# --------------------------------------------------------------------
FROM alpine:3.11

EXPOSE 3000

LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.docker.cmd="docker run -d -p 3000:3000 --name alpine_timeoff"

RUN apk add --no-cache \
    make \
    nodejs npm \
    python3 \
    vim 

RUN addgroup app && adduser --system app --home /app -G app
USER app
WORKDIR /app
COPY --chown=app:app timeoff-management .
WORKDIR /app/timeoff-management
RUN npm install

CMD npm start
