# Uptime Kuma

Este directorio contiene configuraciones de `docker-compose` para desplegar Uptime Kuma en Linux (Ubuntu) y Windows.

## Estructura

- `Ubuntu/docker-compose.yml` — configuración para un entorno Ubuntu/Docker.
- `Windows/docker-compose.yml` — configuración para un entorno Windows/Docker.

## Descripción

El servicio crea un contenedor `uptime-kuma` con la imagen oficial `louislam/uptime-kuma:2`, exponiendo el puerto `3001` y montando un volumen persistente para los datos en `/app/data`.

## Requisitos

- Docker
- Docker Compose

## Ubuntu

1. Instala Docker y Docker Compose si no los tienes:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose
sudo systemctl enable --now docker
```

2. Navega al directorio de Ubuntu y levanta el servicio:

```bash
cd UptimeKuma/Ubuntu
docker compose up -d
```

3. Abre Uptime Kuma en el navegador:

```text
http://localhost:3001
```

## Windows

1. Instala Docker Desktop para Windows.
2. Abre PowerShell y navega al directorio de Windows:

```powershell
cd .\UptimeKuma\Windows
```

3. Ejecuta el compose:

```powershell
docker compose up -d
```

4. Abre Uptime Kuma en el navegador:

```text
http://localhost:3001
```

## Notas

- El contenedor se reinicia automáticamente con `restart: always`.
- Los datos se almacenan en el volumen `uptime-kuma-prod-data`.
- Si modificas el puerto, actualiza `3001:3001` en el `docker-compose.yml` correspondiente.

## Detener y eliminar

Para detener el servicio:

```bash
cd UptimeKuma/Ubuntu
# o
cd UptimeKuma/Windows

docker compose down
```

Para eliminar volúmenes y limpiar datos:

```bash
docker compose down -v
```
