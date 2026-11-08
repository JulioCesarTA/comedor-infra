# SPEC MAESTRO — Plataforma Comedor Universitario UAGRM

> **Instrucciones para el agente (Claude en VS Code / Claude Code):**
> Este documento es la especificación completa y vinculante del proyecto. Debes construir el monorepo descrito abajo, servicio por servicio, siguiendo exactamente la arquitectura de código asignada a cada microservicio, los Dockerfiles, los manifiestos de Kubernetes y el reparto multi-nube indicado. No inventes alcance fuera de lo aquí descrito; si algo es ambiguo, consulta la sección "Resumen de requisitos" como fuente de verdad. Trabaja de forma incremental: primero el monorepo y el `docker-compose.yml` de desarrollo local, luego cada microservicio (empezando por `menu-inventario-service`), luego el frontend, luego IA/automatización, luego los manifiestos K8s por nube, luego CI/CD. Al terminar cada bloque, corre linters/tests y confirma que el `docker-compose up` levanta todo antes de seguir al siguiente.

---

## 0. Contexto del negocio (de la especificación original de la materia)

Plataforma para el Comedor Universitario de la UAGRM que digitaliza el ciclo completo de una ración: planificar el menú, comprar y controlar insumos, reservar y pagar la comida, servirla en la línea de atención y medir cuánto se consumió y cuánto se desperdició. También administra las becas comedor de estudiantes becarios y el cobro de cada ración a estudiantes regulares.

**Problema que resuelve:** hoy el comedor trabaja con tickets en papel, listas impresas de becarios y planillas de inventario. Se forman filas largas, se cocina de más o de menos porque nadie sabe cuántos estudiantes vendrán, se vencen insumos en el almacén, hay becas que no se usan sin que nadie lo note y la dirección no tiene una vista clara del costo real por ración.

### Actores / usuarios

| Actor | Rol |
|---|---|
| Administrador del comedor / Dirección de Bienestar Universitario | Supervisa el servicio, aprueba compras, pide reportes y delega misiones a los agentes de IA |
| Nutricionista | Arma el menú semanal, las recetas y las porciones |
| Personal de cocina y almacén | Registra insumos, producción del día y mermas |
| Personal de servicio y caja | Valida el QR del estudiante en la línea de atención, cobra en efectivo las raciones reservadas y registra entregas |
| Estudiante (regular o becario) | Consulta el menú, reserva su ración, paga por QR bancario o efectivo (becarios no pagan), muestra su QR |
| Proveedor | Recibe órdenes de compra y confirma entregas |

### Componentes de la plataforma

1. Portal del estudiante: menú del día/semana, reservas, pago por QR bancario, estado de la beca, historial, código QR.
2. Sistema de gestión empresarial del comedor (back-office): núcleo del negocio, operado por agentes inteligentes.
3. Módulo de inteligencia de negocio: dashboards y predicciones con Machine Learning.
4. App móvil: modo estudiante y modo punto de servicio, con IA local y funcionamiento offline.
5. Servicios de IA y automatización: agentes, modelos ML/DL, reportes generativos, flujos n8n.

### Funcionalidades principales por módulo

| Módulo | Qué hace |
|---|---|
| Menú e Inventario | Recetas con ficha nutricional, menú semanal por turno (desayuno, almuerzo, cena), insumos por lote con fecha de vencimiento, stock, mermas, órdenes de compra a proveedores, cantidad a cocinar sugerida por IA |
| Comensales y Reservas | Registro de estudiantes vinculado al registro universitario, becas comedor (tipo, cupo, vigencia), reserva de ración por turno, cancelación, lista de espera, control de ingreso con QR |
| Pagos y Tickets | Cobro de cada ración por QR bancario o efectivo en caja, cobertura de beca (becarios no pagan), facturación, devoluciones, pagos a proveedores |
| Inteligencia de negocio | Dashboards de raciones servidas, asistencia, desperdicio y costo por ración; predicción de demanda; segmentación de comensales y platos |
| Agentes de IA | Monitoreo del comedor, planificación de menú, control de inventario y compras, atención al estudiante, reportes generativos por texto o voz |
| App móvil | Estudiante: menú, reserva y QR. Punto de servicio: validar QR offline, registrar entregas, foto de bandeja analizada por IA local |
| Automatización | Reservas y consultas por WhatsApp, recordatorios de reserva, alertas de stock bajo, envío de órdenes de compra y facturas por email, todas las notificaciones push |

---

## 1. Requisito explícito del dueño del proyecto (prioridad sobre el PDF académico en temas de despliegue)

Además de todo lo anterior, el despliegue **debe cumplir obligatoriamente**:

- **Multi-nube real**: un microservicio de negocio desplegado en **AWS**, otro en **Azure** y otro en **Google Cloud Platform (GCP)**.
- **Todo dockerizado**: cada microservicio y cada frontend tiene su propio `Dockerfile` multi-stage, optimizado para producción.
- **Todo kubernetizado**: manifiestos (o Helm charts) de Kubernetes para cada servicio, con `Deployment`, `Service`, `ConfigMap`, `Secret`, `HPA` e `Ingress`, adaptados al clúster administrado de cada nube (EKS, AKS, GKE).
- **Tres motores de base de datos presentes**: **MongoDB**, **DynamoDB** y **PostgreSQL**, cada uno dueño de los datos del/los microservicios que le correspondan según el documento original.
- **Cada microservicio respeta la arquitectura de código que el documento le asigna** (DDD, Hexagonal, Clean o en capas) — no se mezclan ni se simplifican.

### Mapeo de nube ↔ microservicio ↔ base de datos (decisión de arquitectura de este spec)

| Microservicio | Lenguaje/Framework | Arquitectura de código | Base de datos propia | Nube de despliegue | Clúster K8s |
|---|---|---|---|---|---|
| `menu-inventario-service` | Java / Spring Boot | **DDD** (Domain-Driven Design) | **MongoDB** | **AWS** | Amazon EKS |
| `comensales-reservas-service` | TypeScript / NestJS | **Clean Architecture** | **PostgreSQL** (instancia propia) | **Azure** | Azure AKS |
| `pagos-tickets-service` | PHP / Laravel | **Arquitectura Hexagonal** | **PostgreSQL** (instancia propia, separada de la anterior) | **Google Cloud** | Google GKE |
| `ia-ml-service` | Python / FastAPI | **En capas** (layered) | Lee de la base de lectura CQRS (PostgreSQL) | **AWS** (junto a infraestructura de soporte) | Amazon EKS |

**DynamoDB** es transversal y vive en AWS (es nativo de AWS, no existe equivalente gestionado idéntico en Azure/GCP): guarda claves de idempotencia, estado de las sagas y el registro de operaciones que llegan desde la cola offline. Los microservicios en Azure y GCP acceden a él vía API HTTPS autenticada con IAM (a través de un endpoint expuesto por el `saga-orchestrator` / API Gateway en AWS), nunca con SDK directo cruzando nube — esto se documenta como decisión de arquitectura explícita (trade-off de latencia cross-cloud aceptado a cambio de cumplir el requisito de las tres nubes).

La **base de lectura CQRS** (consolidado de los tres microservicios de negocio, usada por reportes, dashboards y agentes) vive en PostgreSQL en AWS, alimentada por eventos del bus (SNS/SQS).

---

## 2. Monorepo — estructura de carpetas obligatoria

```
comedor-uagrm/
├── docker-compose.yml                 # levanta TODO el stack en local (3 nubes simuladas localmente)
├── docker-compose.override.yml
├── .env.example
├── Makefile                           # make up / make down / make test / make deploy-aws / etc.
│
├── services/
│   ├── menu-inventario-service/       # Spring Boot (Java) — DDD — MongoDB
│   ├── comensales-reservas-service/   # NestJS (TypeScript) — Clean — PostgreSQL
│   ├── pagos-tickets-service/         # Laravel (PHP) — Hexagonal — PostgreSQL
│   └── ia-ml-service/                 # FastAPI (Python) — Capas — lee CQRS read DB
│
├── gateway/
│   ├── api-gateway/                   # punto de entrada REST único (Kong / Spring Cloud Gateway)
│   └── graphql-gateway/               # Apollo Federation, solo para el back-office Angular
│
├── eventbus/
│   └── infra/                         # definiciones de topics/colas SQS+SNS (o LocalStack en dev)
│
├── auth/
│   └── keycloak/                      # realm export, roles, clientes OIDC
│
├── frontend/
│   ├── shell/                         # React + Module Federation (host)
│   ├── backoffice-gestion/            # Angular — GraphQL — remote del shell
│   ├── portal-estudiante/             # React — REST — remote del shell
│   └── inteligencia-negocio/          # React — REST — remote del shell
│
├── mobile/
│   └── app-movil/                     # React Native — modo estudiante + modo punto de servicio
│
├── automation/
│   └── n8n/
│       ├── flows/                     # JSON exportado de cada flujo
│       │   ├── flujo-reserva-whatsapp.json
│       │   └── flujo-reposicion-insumos.json
│       └── docker-compose.n8n.yml
│
├── ml/
│   ├── notebooks/                     # entrenamiento de los 6 modelos
│   ├── models/                        # artefactos entrenados (.onnx, .tflite, TF.js)
│   └── training-pipelines/
│
├── infra/
│   ├── k8s/
│   │   ├── aws/
│   │   │   ├── menu-inventario-service/
│   │   │   ├── ia-ml-service/
│   │   │   ├── api-gateway/
│   │   │   └── dynamodb-access/
│   │   ├── azure/
│   │   │   └── comensales-reservas-service/
│   │   └── gcp/
│   │       └── pagos-tickets-service/
│   ├── terraform/
│   │   ├── aws/                       # EKS, DynamoDB, S3, SQS/SNS
│   │   ├── azure/                     # AKS, PostgreSQL Flexible Server
│   │   └── gcp/                       # GKE, Cloud SQL (Postgres)
│   └── helm/                          # charts opcionales por servicio
│
├── .github/
│   └── workflows/
│       ├── ci-menu-inventario.yml
│       ├── ci-comensales-reservas.yml
│       ├── ci-pagos-tickets.yml
│       ├── ci-ia-ml.yml
│       ├── cd-aws.yml
│       ├── cd-azure.yml
│       └── cd-gcp.yml
│
└── docs/
    └── iconix/
        ├── 01-modelo-dominio.md
        ├── 02-casos-de-uso/
        ├── 03-diagramas-robustez/
        ├── 04-diagramas-secuencia/
        └── 05-diagramas-clases/
```

---

## 3. Microservicios de negocio (detalle)

### 3.1 `menu-inventario-service` — Spring Boot (Java) — DDD — MongoDB — AWS

**Responsabilidad:** recetas, platos, menú semanal, insumos por lote, stock, mermas, órdenes de compra.

**Por qué MongoDB:** cada receta tiene ingredientes, pasos y ficha nutricional distintos, y cada insumo tiene atributos propios (lote, vencimiento, unidad); un documento flexible evita tablas llenas de columnas vacías.

**Agregados DDD a implementar:**
- `Menu` (raíz): reglas — no se publica un menú sin receta ni porciones; no se aparta una porción si no hay stock.
- Objetos de valor: `Porcion`, `Cantidad`, `FechaVencimiento`.
- Eventos de dominio: `StockBajoEvent`, `LoteVencidoEvent`, `PorcionApartadaEvent`, `PorcionLiberadaEvent` (publicados al bus SNS).

**Estructura de paquetes (DDD táctico):**
```
menu-inventario-service/
├── src/main/java/com/uagrm/comedor/menu/
│   ├── domain/
│   │   ├── model/          # Menu, Plato, Receta, Insumo, Lote (entidades y VOs)
│   │   ├── event/          # eventos de dominio
│   │   ├── repository/     # interfaces (puertos de salida)
│   │   └── service/        # domain services
│   ├── application/
│   │   ├── usecase/        # ArmarMenuSemanal, ApartarPorcion, RegistrarMerma, GenerarOrdenCompra...
│   │   └── dto/
│   ├── infrastructure/
│   │   ├── persistence/mongo/   # repos Spring Data MongoDB
│   │   ├── messaging/           # publisher/listener SNS/SQS
│   │   ├── mcp/                 # servidor MCP: expone tools "consultar_menu", "ver_stock_insumo"
│   │   └── web/                 # controllers REST
│   └── config/
├── Dockerfile
└── pom.xml
```

**Endpoints REST clave:** `GET /menus/semana/{turno}`, `POST /menus`, `POST /insumos/lotes`, `GET /insumos/stock-bajo`, `POST /ordenes-compra`, `POST /porciones/apartar` (usado por la saga), `POST /porciones/liberar` (compensación).

**Herramientas MCP que expone:** `consultar_menu`, `ver_stock_insumo`, `sugerir_cantidad_cocinar`, `crear_orden_compra_borrador`.

### 3.2 `comensales-reservas-service` — NestJS (TypeScript) — Clean Architecture — PostgreSQL — Azure

**Responsabilidad:** estudiantes, becas, turnos, reservas, lista de espera, control de ingreso con QR.

**Capas Clean (de adentro hacia afuera, dependencias apuntando hacia adentro):**
```
comensales-reservas-service/
├── src/
│   ├── entities/            # Estudiante, Beca, Reserva, Turno (reglas de negocio puras, sin frameworks)
│   ├── use-cases/           # ReservarRacion, CancelarReserva, ValidarIngreso, ListaEspera
│   ├── interface-adapters/
│   │   ├── controllers/     # REST controllers
│   │   ├── presenters/
│   │   └── gateways/        # implementación de los puertos de los use-cases
│   └── infrastructure/
│       ├── database/postgres/   # TypeORM/Prisma, migraciones
│       ├── messaging/           # SNS/SQS producer-consumer
│       ├── mcp/                 # servidor MCP: "crear_reserva", "consultar_beca"
│       └── http/                # bootstrap Nest, main.ts
├── Dockerfile
└── package.json
```

**Endpoints clave:** `GET /estudiantes/{id}/beca`, `POST /reservas` (paso 1 de la saga, estado `pendiente`), `POST /reservas/{id}/confirmar` (paso 4 de la saga), `POST /reservas/{id}/cancelar` (compensación / saga de cancelación), `POST /ingreso/validar-qr`.

### 3.3 `pagos-tickets-service` — Laravel (PHP) — Hexagonal — PostgreSQL (propia) — GCP

**Responsabilidad:** cobro de cada ración (QR bancario o efectivo en caja), cobertura de becas, facturación, devoluciones, pagos a proveedores.

**Puertos y adaptadores:**
```
pagos-tickets-service/
├── app/
│   ├── Domain/               # núcleo hexagonal: Pago, Ticket, Factura, Beca (reglas puras)
│   ├── Application/
│   │   ├── Ports/
│   │   │   ├── Inbound/      # CobrarRacionUseCase, DevolverPagoUseCase...
│   │   │   └── Outbound/     # PaymentGatewayPort, RepositoryPort, NotificationPort
│   │   └── Services/         # implementación de los casos de uso
│   └── Infrastructure/
│       ├── Adapters/
│       │   ├── Persistence/postgres/   # Eloquent/repos concretos
│       │   ├── QrBancario/             # adaptador a la pasarela de pago real
│       │   └── Messaging/              # SNS/SQS
│       ├── Mcp/                        # servidor MCP: "cobrar_racion", "consultar_estado_pago"
│       └── Http/Controllers/           # REST
├── Dockerfile
└── composer.json
```

**Endpoints clave:** `POST /pagos/cobrar` (paso 3 de la saga: aplica beca o cobra QR/efectivo, emite ticket), `POST /pagos/{id}/devolver` (compensación), `POST /facturas`, `POST /proveedores/pagos`.

**Importante:** el núcleo de dominio (`app/Domain`) no debe importar nada de Laravel, Eloquent ni del framework — solo PHP puro, tal como exige Hexagonal.

### 3.4 `ia-ml-service` — Python / FastAPI — Arquitectura en capas — AWS

**Responsabilidad:** modelos de ML/DL, agentes inteligentes, servidor MCP cliente/orquestador, reportes generativos.

```
ia-ml-service/
├── app/
│   ├── api/              # capa API: routers FastAPI
│   ├── services/         # capa de servicios: agentes, orquestación MCP, generación de reportes
│   ├── models/            # capa de modelos: wrappers de los modelos entrenados (ML/DL)
│   ├── data/              # capa de acceso a datos: cliente a la base de lectura CQRS (Postgres)
│   └── agents/
│       ├── monitor_comedor_agent.py
│       ├── planificador_menu_agent.py
│       ├── inventario_compras_agent.py
│       └── atencion_estudiante_agent.py
├── Dockerfile
└── requirements.txt
```

**Modelos a entrenar y exponer (ver sección 6):** predicción de demanda, probabilidad de no-presentación, segmentación de comensales, agrupamiento de platos, CNN de desperdicio en bandeja, clasificación de calidad de insumos.

**Agentes (misión → skills vía MCP, nunca SQL directo):**

| Agente | Misión | Skills (tools MCP que consume de los otros 3 microservicios) |
|---|---|---|
| Monitor del comedor | "Monitorea el comedor y avísame lo importante" | detectar caída de asistencia, platos con mucho desperdicio, costo por ración fuera de presupuesto, reporte diario |
| Planificador de menú | "Arma el menú de la próxima semana" | proponer menú según recetas aceptadas, stock, insumos por vencer, predicción de demanda |
| Inventario y compras | "Que nunca falte un insumo ni se venza nada" | detectar stock bajo y lotes por vencer, preparar órdenes de compra, escalar al administrador |
| Atención al estudiante | "Que ningún estudiante quede sin respuesta" | responder consultas de menú/horarios/precios/beca, gestionar reservas y cancelaciones |

Las acciones críticas (emitir orden de compra, suspender una beca) requieren confirmación humana explícita antes de ejecutarse — no se auto-aprueban.

---

## 4. API Gateway, GraphQL y bus de eventos

- **API Gateway:** punto de entrada REST único para los frontends (Kong o Spring Cloud Gateway). Enruta a los tres microservicios de negocio y al `ia-ml-service`, valida el JWT de Keycloak.
- **GraphQL (Apollo Federation):** gateway GraphQL **solo** para el back-office Angular, federando los subgrafos de `menu-inventario-service`, `comensales-reservas-service` y `pagos-tickets-service`. Todo lo demás (portal, app móvil, inteligencia de negocio, n8n, comunicación entre microservicios) usa **REST**. Los reportes no pasan por GraphQL: leen de la base de lectura CQRS por REST.
- **Bus de eventos:** Amazon SNS/SQS. Cada microservicio publica sus eventos de dominio (`PorcionApartada`, `ReservaConfirmada`, `PagoRealizado`, `StockBajo`, etc.) y los consume quien lo necesite — en particular el proyector que alimenta la base de lectura CQRS en PostgreSQL.

---

## 5. Transacciones transversales — patrón Saga (orquestada, estado en DynamoDB)

Cada microservicio tiene su propia base de datos → no existe rollback común. Las operaciones que cruzan los tres microservicios de negocio se coordinan con una saga orquestada; si un paso falla, se ejecutan compensaciones. El estado de cada saga se guarda en DynamoDB.

### Saga 1: Reservar y pagar una ración

| Paso | Microservicio | Acción | Compensación si algo falla después |
|---|---|---|---|
| 1 | Comensales y Reservas | Validar estudiante, crear reserva en estado `pendiente` para el turno elegido | Cancelar la reserva |
| 2 | Menú e Inventario | Apartar una porción del plato del turno (descontar del cupo) | Devolver la porción al cupo |
| 3 | Pagos y Tickets | Si es becario, aplicar beca; si no, cobrar (QR bancario o efectivo en caja). Emitir ticket | Devolver el pago o liberar la beca, anular el ticket |
| 4 | Comensales y Reservas | Confirmar la reserva y generar el código QR | Invalidar el QR |

### Saga 2: Cancelar una reserva (devolución)

Pagos y Tickets devuelve el pago (o libera la ración de la beca) → Menú e Inventario libera la porción → Comensales y Reservas marca la reserva como cancelada y ofrece el cupo a la lista de espera. Si la devolución falla, la porción no se libera.

**Implementación obligatoria:** `saga-orchestrator` como proceso/servicio dentro de `ia-ml-service` o como lambda/worker independiente en AWS, con máquina de estados persistida en DynamoDB (tabla `sagas` con `sagaId`, `step`, `status`, `payload`, `compensations[]`).

---

## 6. Offline, idempotencia y sincronización (back-office PWA + app móvil)

- Back-office (PWA) y app móvil guardan datos localmente (IndexedDB en web, SQLite en móvil).
- El punto de servicio descarga al inicio de cada turno la lista de reservas y becarios; el QR se valida contra esa lista aunque se caiga internet.
- Toda operación sin conexión entra en una cola de sincronización; al volver la red se envía en orden con reintentos automáticos con backoff exponencial (1s, 2s, 4s, 8s).
- **Idempotencia:** cada operación lleva una clave única generada en el cliente (p. ej. al registrar una entrega o un cobro QR). El servidor guarda esa clave en **DynamoDB con escritura condicional** (`ConditionExpression: attribute_not_exists(idempotencyKey)`); si la misma petición llega dos veces, la segunda se reconoce y devuelve el resultado original sin duplicar el efecto.
- La UI muestra el estado de cada operación: pendiente, sincronizada, con error.
- Las reservas y raciones se sincronizan primero en paquetes pequeños; las fotos de bandejas se suben después.

---

## 7. IA local (on-device)

- **App móvil (React Native):** TensorFlow Lite — modelo CNN que estima, a partir de la foto de la bandeja devuelta, el porcentaje de comida sobrante por componente (arroz, carne, ensalada). Registro de mermas/producción por nota de voz transcrita en el dispositivo.
- **Back-office (PWA, navegador):** TensorFlow.js o Transformers.js — búsqueda semántica de recetas ("plato con pollo, bajo en grasa y sin lácteos") y resumen de fichas, sin depender del servidor.
- Los modelos de imagen (CNN de desperdicio, clasificación de calidad de insumos) se entrenan en `ml/` y se exportan a TensorFlow Lite (móvil) y TensorFlow.js (navegador).

---

## 8. Machine Learning y Deep Learning — catálogo de modelos

| Tipo | Modelo | Uso |
|---|---|---|
| Supervisado (regresión) | Predicción de raciones por turno según día, plato, calendario académico y clima | Cantidad sugerida a cocinar |
| Supervisado (clasificación) | Probabilidad de no-presentación de una reserva | Sobrereserva controlada, liberar cupo a lista de espera |
| No supervisado (clustering) | Segmentación de comensales por frecuencia, horario, preferencias y tipo de beca | Menús/campañas dirigidas, detección de becarios inactivos |
| No supervisado (clustering) | Agrupamiento de platos por aceptación, costo y desperdicio | Mapa de platos en dashboards |
| Deep Learning (CNN, imagen) | Estimación de % de comida sobrante en foto de bandeja | Medir desperdicio por plato/turno |
| Deep Learning (CNN, imagen) | Clasificación de calidad de insumos recibidos | Control de calidad al recibir al proveedor |

Todos los modelos se sirven desde `ia-ml-service` vía FastAPI; las versiones ligeras de los modelos de imagen se exportan para correr on-device (sección 7).

---

## 9. Automatización con n8n

n8n orquesta flujos 100% automáticos que conectan WhatsApp (vía **Kapso**), los microservicios y el email. n8n también maneja TODAS las notificaciones: emails, WhatsApp y push (Firebase Cloud Messaging). El envío de notificaciones **no es un microservicio**, lo hace n8n.

**Flujo 1 — Reserva por WhatsApp:**
1. Estudiante escribe "¿qué hay de almuerzo mañana?".
2. n8n consulta el menú en `menu-inventario-service` y responde con plato y precio.
3. Si pide reservar, n8n lo identifica por su número registrado y dispara la Saga 1. Si no es becario, le envía el QR bancario para pagar.
4. n8n envía por WhatsApp la confirmación con el código QR.

**Flujo 2 — Reposición de insumos:**
1. Cada noche n8n consulta en `menu-inventario-service` los insumos bajo stock mínimo y los que necesita el menú de la semana siguiente.
2. Genera un borrador de orden de compra y lo envía al administrador para aprobación.
3. Al aprobarse, `pagos-tickets-service` registra la obligación de pago al proveedor.
4. n8n envía la orden por email al proveedor y avisa al almacén la fecha de entrega.

---

## 10. Reportes generativos y protección contra inyección SQL

- Petición en lenguaje natural (texto o voz) → transcripción → el modelo de lenguaje **elige entre consultas predefinidas y completa parámetros** (nunca escribe SQL libre).
- Parámetros validados por tipo y rango, enviados como consultas parametrizadas.
- Los reportes leen de la **base de lectura CQRS con un usuario de solo lectura**.
- Cada petición queda registrada (auditoría); el usuario solo ve datos que su rol permite — mismo control aplica a comandos de voz, WhatsApp y herramientas MCP de los agentes.
- Resultado mostrado en pantalla como tabla/gráfico, exportable a Excel y PDF.

---

## 11. Autenticación — SSO con Keycloak

Keycloak con OpenID Connect. Login único para portal, back-office, dashboards y app móvil. Estudiantes ingresan con su registro universitario. Roles: `administrador`, `nutricionista`, `cocina_almacen`, `servicio_caja`, `estudiante` — cada rol define qué módulos y qué datos puede ver/mutar.

---

## 12. Arquitectura — los 4 niveles

1. **Backend:** microservicios independientes detrás de un API Gateway, comunicados por REST y por eventos asíncronos (SNS/SQS).
2. **Frontend:** microfrontends Angular y React integrados por el shell con Module Federation, más la app móvil en React Native.
3. **Datos:** cada servicio tiene su propia base (poliglota: MongoDB, PostgreSQL×2, DynamoDB); CQRS con base de lectura consolidada en PostgreSQL alimentada por eventos — ahí consultan reportes, dashboards y agentes.
4. **Despliegue:** Docker en todos los servicios; Kubernetes gestionado por nube (EKS/AKS/GKE) según el mapeo de la sección 1; CI/CD con GitHub Actions por servicio y por nube.

---

## 13. Frontend y app móvil

| Pieza | Framework | Contenido | Consume |
|---|---|---|---|
| Shell | React (Module Federation host) | Menú y navegación general, sesión única, carga de los demás microfrontends | — |
| Back-office de gestión | Angular | Menú/inventario, compras, comensales/becas, reservas, pagos, panel de agentes IA | GraphQL (Apollo Federation) |
| Portal del estudiante | React | Menú del día, reservas, pago QR bancario, estado de beca, historial, QR | REST |
| Inteligencia de negocio | React | Dashboards, predicciones, reportes generativos | REST |
| App móvil | React Native | Modo estudiante (menú, reserva, QR) + modo punto de servicio (validar QR offline, registrar entregas, foto de bandeja con IA local) | REST + IA local (TFLite) |

---

## 14. Metodología ICONIX (documentación obligatoria en `docs/iconix/`)

Cuatro etapas, pocos diagramas UML, todos conectados entre sí:

1. **Análisis de requisitos:** modelo de dominio (clases `Estudiante`, `Beca`, `Reserva`, `Turno`, `Menu`, `Plato`, `Receta`, `Insumo`, `Lote`, `Pago`, `Ticket`, `Proveedor`, `OrdenCompra`), prototipos de pantalla, casos de uso.
2. **Análisis y diseño preliminar:** descripción de cada caso de uso + diagrama de robustez, revisados contra el modelo de dominio.
3. **Diseño detallado:** diagramas de secuencia (obligatorio: secuencia de la Saga 1 completa) y diagrama de clases final por microservicio.
4. **Implementación:** código y pruebas por caso de uso, incluido el caso en que falla el pago dentro de la saga (prueba de compensación).

**Casos de uso principales por actor** (mínimo a documentar y testear):
- Estudiante: consultar menú, reservar ración, cancelar reserva, pagar ración por QR bancario, mostrar QR, consultar por WhatsApp.
- Personal de servicio y caja: validar QR, registrar ración entregada, fotografiar bandeja, cobrar ración en efectivo.
- Nutricionista: registrar receta, armar menú semanal, revisar aceptación de platos.
- Personal de cocina y almacén: registrar ingreso de insumos, registrar producción, registrar merma.
- Administrador: aprobar orden de compra, gestionar becas, pedir reporte generativo, dar misión a un agente.
- Agentes de IA y n8n: alertar stock bajo, proponer menú, enviar recordatorios, generar orden de compra.

**Ejemplo de robustez obligatorio — caso "Reservar ración":**
- Interfaz: pantalla de reserva del portal/app; chat de WhatsApp.
- Control: orquestador de la Saga 1; validador de beca y de pago.
- Entidades: Estudiante, Reserva, Porción del menú, Beca, Pago, Ticket.

---

## 15. Docker y Kubernetes — requisitos técnicos obligatorios

### 15.1 Docker

- Cada microservicio y cada frontend tiene su propio `Dockerfile` **multi-stage** (build + runtime mínimo, ej. `eclipse-temurin:21-jre-alpine` para Spring Boot, `node:20-alpine` para NestJS/React/Angular, `php:8.3-fpm-alpine` + nginx para Laravel, `python:3.12-slim` para FastAPI).
- Usuario no-root dentro del contenedor, `HEALTHCHECK` definido, variables de entorno vía `.env`/ConfigMap, nunca secretos hardcodeados.
- `docker-compose.yml` raíz levanta TODO el stack en local: los 4 microservicios, MongoDB, 2 instancias de PostgreSQL, DynamoDB Local, LocalStack (SQS/SNS/S3), Keycloak, n8n, los 4 frontends y el gateway — para que el equipo desarrolle sin depender de las nubes reales.

### 15.2 Kubernetes

Para cada servicio, manifiestos (o chart Helm) con, como mínimo:
- `Deployment` (readiness/liveness probes, resource requests/limits, 2+ réplicas).
- `Service` (ClusterIP interno; el API Gateway expone `LoadBalancer`/`Ingress`).
- `ConfigMap` para configuración no sensible.
- `Secret` para credenciales de BD, claves JWT, API keys (gestionadas con External Secrets / Key Vault / Secrets Manager / Secret Manager según la nube).
- `HorizontalPodAutoscaler` basado en CPU/memoria.
- `Ingress` (NGINX Ingress Controller o el ingress nativo de cada nube) con TLS.

**Particularidades por nube:**
- **AWS (EKS)** — `menu-inventario-service`, `ia-ml-service`, API Gateway, acceso a DynamoDB vía IRSA (IAM Roles for Service Accounts).
- **Azure (AKS)** — `comensales-reservas-service`, PostgreSQL Flexible Server, Key Vault para secretos vía CSI driver.
- **GCP (GKE)** — `pagos-tickets-service`, Cloud SQL (Postgres) vía Cloud SQL Auth Proxy como sidecar, Secret Manager.

---

## 16. CI/CD

- Un workflow de GitHub Actions por microservicio (`.github/workflows/ci-*.yml`): lint → test unitario → test de integración (con contenedores efímeros vía testcontainers) → build de imagen Docker → push a registry (ECR/ACR/Artifact Registry según la nube destino).
- Un workflow de despliegue por nube (`cd-aws.yml`, `cd-azure.yml`, `cd-gcp.yml`) que aplica los manifiestos K8s (`kubectl apply` o `helm upgrade --install`) al clúster correspondiente tras el build exitoso.

---

## 17. Resumen de requisitos → dónde se aplica (tabla de verificación / Definition of Done)

| Requisito | Dónde se aplica |
|---|---|
| Microservicios (Spring Boot, NestJS, PHP) | `menu-inventario-service`, `comensales-reservas-service`, `pagos-tickets-service`; además `ia-ml-service` (Python) |
| Microfrontends + shell (Angular, React, React Native) | `shell` (React), `backoffice-gestion` (Angular), `portal-estudiante` + `inteligencia-negocio` (React), `app-movil` (React Native) |
| GraphQL | Solo en el back-office (gateway Apollo Federation) |
| API REST | Portal, app móvil, comunicación entre microservicios, n8n |
| Agentes inteligentes | Monitor del comedor, planificador de menú, inventario y compras, atención al estudiante |
| Protocolo MCP | Herramientas que cada microservicio expone a los agentes |
| IA local | App móvil (foto de bandeja + voz) y navegador (búsqueda de recetas y resumen) |
| Offline + PWA | Back-office PWA y app móvil: validación de QR sin internet, cola de sincronización, manejo de conexión inestable |
| Idempotencia | Claves únicas por operación registradas en DynamoDB |
| Transacciones transversales + Saga | Reservar y pagar ración; cancelar reserva |
| ML supervisado | Predicción de demanda de raciones y de inasistencia |
| ML no supervisado | Segmentación de comensales y de platos |
| Deep Learning (TensorFlow, imagen) | Estimación de desperdicio en bandejas; calidad de insumos |
| Automatización n8n | Reservas por WhatsApp (vía Kapso); reposición de insumos |
| Reportes generativos (texto y voz) | Reportes en pantalla, Excel y PDF |
| Protección contra inyección SQL | Consultas predefinidas y parametrizadas, usuario de solo lectura |
| PostgreSQL, MongoDB, DynamoDB | Reservas y Pagos (Postgres); Menú e Inventario (Mongo); idempotencia y sagas (DynamoDB) |
| Inicio de sesión único | Keycloak con OpenID Connect |
| DDD, Hexagonal, Clean | Menú e Inventario (DDD), Pagos y Tickets (Hexagonal), Comensales y Reservas (Clean) |
| Cuatro niveles de arquitectura | Backend, frontend, datos (CQRS), despliegue multi-nube |
| **Multi-nube (AWS + Azure + GCP)** | **`menu-inventario-service`+`ia-ml-service`→AWS, `comensales-reservas-service`→Azure, `pagos-tickets-service`→GCP** |
| **Dockerizado** | **Dockerfile multi-stage por servicio + `docker-compose.yml` de desarrollo** |
| **Kubernetizado** | **Manifiestos/Helm por servicio en `infra/k8s/{aws,azure,gcp}/`** |
| Documentación | Metodología ICONIX: modelo de dominio, casos de uso, robustez y secuencia |

---

## 18. Orden de implementación sugerido para el agente

1. Monorepo + `docker-compose.yml` local (todas las infra de soporte: Mongo, 2x Postgres, DynamoDB Local, LocalStack, Keycloak, n8n).
2. `menu-inventario-service` completo (DDD) con tests.
3. `comensales-reservas-service` completo (Clean) con tests.
4. `pagos-tickets-service` completo (Hexagonal) con tests.
5. `saga-orchestrator` (Saga 1 y 2) + idempotencia en DynamoDB.
6. `ia-ml-service` (capas) con endpoints stub para los 6 modelos + los 4 agentes vía MCP.
7. API Gateway REST + GraphQL Gateway (Apollo Federation).
8. Frontend: `shell` → `backoffice-gestion` → `portal-estudiante` → `inteligencia-negocio`.
9. `app-movil` (React Native) con IA local y modo offline.
10. n8n: flujo WhatsApp (Kapso) y flujo de reposición.
11. Manifiestos Kubernetes por nube + Terraform base + workflows CI/CD.
12. Documentación ICONIX completa en `docs/iconix/`.
13. Checklist final contra la tabla de la sección 17.
