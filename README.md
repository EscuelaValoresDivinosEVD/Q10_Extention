# Q10 Extension — CLEV

Aplicación Rails que conecta el flujo de acceso de estudiantes CLEV con **Q10** y **Pagomedios**: consulta deudas, cobro en línea y reporte automático del pago en Q10.

## ¿Qué hace?

1. El estudiante ingresa tipo y número de documento + correo en la página de acceso.
2. La app valida al estudiante contra la API de Q10 y envía un enlace de continuación por correo.
3. Desde ese enlace, el estudiante ve sus deudas en Q10 y puede pagar con Pagomedios.
4. Tras un cobro exitoso, el pago se registra en la base de datos y se reporta a Q10.

## Stack

- Ruby **3.4.4**
- Rails **8.0**
- PostgreSQL
- Hotwire (Turbo + Stimulus)
- Integraciones: Q10 API, Pagomedios, SparkPost (producción)

## Requisitos

- Ruby 3.4.4 (ver `.ruby-version`)
- PostgreSQL
- Bundler

## Configuración local

```bash
# Clonar e instalar dependencias
git clone git@github-cesvald:EscuelaValoresDivinosEVD/Q10_Extention.git
cd Q10_Extention
bundle install

# Variables de entorno
cp .env.example .env
# Edita .env con tus credenciales

# Base de datos
cp config/database.yml.example config/database.yml
bin/rails db:create db:migrate

# Levantar servidor
bin/dev
# o: bin/rails server
```

La app queda disponible en `http://localhost:3000`.

En desarrollo, los correos se abren en el navegador en `/letter_opener` (no hace falta configurar SMTP).

## Variables de entorno

| Variable | Descripción |
|---|---|
| `PAGOMEDIOS_API_TOKEN` | Token de Pagomedios (obligatorio) |
| `Q10_SUBSCRIPTION_KEY` | Clave de suscripción Q10 |
| `Q10_API_KEY` | API key Q10 |
| `Q10_CODIGO_CAJERO` | Código de cajero para reportar pagos en Q10 |
| `Q10_API_BASE_URL` | URL base de la API (por defecto `https://api.q10.com/v1`) |
| `Q10_ENABLED` | Activa/desactiva integración Q10 (`true` / `false`) |
| `Q10_SKIP_CREDITOS_CHECK` | Solo desarrollo: omite validación de créditos en Q10 |
| `APP_HOST` | Host público en producción (URLs de correo) |
| `SPARKPOST_SMTP_API_KEY` | SMTP en producción |

Consulta `.env.example` para la lista completa.

## Rutas principales

| Ruta | Descripción |
|---|---|
| `/` | Formulario de acceso CLEV |
| `/continuar?token=...` | Panel de deudas Q10 del estudiante |
| `/pagar` | Formulario de pago Pagomedios |
| `/pagos/resultado` | Resultado del pago |
| `/payments/webhook` | Callback de Pagomedios |
| `/up` | Health check |

## Despliegue en Heroku

```bash
heroku create clev-evd
heroku addons:create heroku-postgresql:essential-0
heroku config:set SOLID_QUEUE_IN_PUMA=true
heroku config:set APP_HOST=clev.evdsky.com
heroku config:set ALLOWED_HOSTS=clev.evdsky.com
# Configura también PAGOMEDIOS_*, Q10_*, SPARKPOST_* y RAILS_MASTER_KEY

git push heroku main
```

El `Procfile` levanta Puma y en cada release corre `heroku:release` (migraciones + tablas Solid Queue/Cache/Cable).

## Tests

```bash
bin/rails db:test:prepare test
```

## Estructura relevante

```
app/
  controllers/   # home, q10_debts, payments
  services/      # Q10::ApiClient, PagomediosService, PaymentRecorder
  models/        # Payment
  mailers/       # StudentAccessMailer
```

## Organización

Proyecto de [Escuela Valores Divinos EVD](https://github.com/EscuelaValoresDivinosEVD).
