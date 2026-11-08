# ✅ Checklist del Parcial — Plataforma Comedor Universitario UAGRM

> Marca `[x]` cada punto cumplido y escribe **dónde/cómo** lo aplicas.
> Regla del ingeniero: todo debe aparecer **en algún lugar** del proyecto y debe ser **pertinente**, no puesto solo por cumplir.

---

## 1. Microservicios (mínimo 3)

- [ ] Existen **al menos 3 microservicios**
- [ ] Un microservicio en **Spring Boot**
  - Cuál / responsabilidad: `____________________`
- [ ] Un microservicio en **NestJS**
  - Cuál / responsabilidad: `____________________`
- [ ] Un microservicio en **PHP**
  - Cuál / responsabilidad: `____________________`
- [ ] (Opcional) Otros microservicios en otros lenguajes: `____________________`

---

## 2. Frontends (mínimo 3)

- [ ] Frontend en **Angular**
  - Para qué / quién lo usa: `____________________`
- [ ] Frontend en **React**
  - Para qué / quién lo usa: `____________________`
- [ ] Tercer frontend (tecnología libre): `____________________`
- [ ] Al menos un frontend es **aplicación móvil**
- [ ] Hay un **BFF / API Gateway** entre los frontends y los microservicios *(confirmar con el ingeniero qué quiso decir con "fiel")*

---

## 3. GraphQL y REST

- [ ] **GraphQL** aplicado en el **sistema de gestión empresarial** (interacción front ↔ usuarios)
  - Dónde: `____________________`
- [ ] El resto de la comunicación usa **APIs REST**
- [ ] Puedo explicar **por qué GraphQL** y no REST en esa parte (menos endpoints, solo los datos necesarios, etc.)

---

## 4. Agentes inteligentes

- [ ] Las funcionalidades del sistema de gestión están construidas **como agentes**
- [ ] Cada agente tiene una **misión** y un conjunto de **skills**
  - Agente 1 — misión: `____________________` / skills: `____________________`
  - Agente 2 — misión: `____________________` / skills: `____________________`
- [ ] Los agentes **reportan** información del negocio (ej.: monitoreo del comedor: ventas, raciones, stock)

---

## 5. IA local y funcionamiento offline

- [ ] **IA local en el móvil**
  - Qué hace: `____________________`
- [ ] **IA local en el navegador** (front web)
  - Qué hace: `____________________`
- [ ] El **móvil funciona sin internet**
- [ ] La **web funciona sin internet** (PWA / Service Workers / almacenamiento local)
- [ ] La app soporta **internet inestable** (cortes intermitentes, reintentos, timeouts)
- [ ] Hay un **mecanismo de sincronización** al recuperar conexión
- [ ] Se garantiza **idempotencia**: una transacción **no se registra dos veces** por fallas de red
  - Cómo (ej.: clave de idempotencia, UUID por operación): `____________________`

---

## 6. Transacciones distribuidas

- [ ] Existe al menos **una acción que involucra 3 o más microservicios**
  - Acción: `____________________`
  - Microservicios que intervienen: `________` → `________` → `________`
- [ ] Está resuelto qué pasa si **uno falla** a mitad de proceso
- [ ] Se aplica el **patrón Saga** (orquestación o coreografía) con **compensaciones**
  - Tipo de Saga: `____________________`
  - Compensaciones definidas: `____________________`

---

## 7. Machine Learning y Deep Learning

- [ ] **ML supervisado**
  - Uso (ej.: predecir demanda de raciones): `____________________`
- [ ] **ML no supervisado**
  - Uso (ej.: segmentar estudiantes por hábitos de consumo): `____________________`
- [ ] **Deep Learning con TensorFlow**
- [ ] El DL procesa **imágenes o video**
  - Uso (ej.: reconocer platos, controlar acceso, medir desperdicio): `____________________`

---

## 8. Automatización con n8n

- [ ] Existe un flujo **100% automatizado en n8n**
- [ ] El flujo **pasa por varios microservicios / sistemas**
  - Flujo: `________` → `________` → `________` → `________`
  - (Ejemplo del ingeniero: pedido por WhatsApp → sistema de gestión → facturación → envío de email)

---

## 9. Reportes generativos

- [ ] Los reportes se piden en **lenguaje natural (texto)**
- [ ] Los reportes se pueden pedir **por audio (voz)**
- [ ] El reporte se **muestra en pantalla**
- [ ] El reporte se puede **exportar a Excel** (u otro formato)
  - Ejemplo de pregunta: `____________________`

---

## 10. Protocolo MCP

- [ ] Se usa **MCP (Model Context Protocol)** en alguna parte
  - Dónde / para qué: `____________________`

---

## 11. Seguridad

- [ ] Protección contra **inyección SQL**
- [ ] Protección contra **inyección de prompts** en los agentes / MCP
- [ ] Los **reportes generativos** no ejecutan consultas peligrosas (solo lectura, validación, consultas parametrizadas)
- [ ] Los comandos de los agentes/MCP tienen **permisos limitados**

---

## 12. Bases de datos (mínimo 3)

- [ ] Base **relacional**: PostgreSQL / Oracle / SQL Server (**NO MySQL**)
  - Cuál y en qué microservicio: `____________________`
- [ ] **MongoDB**
  - En qué microservicio: `____________________`
- [ ] **DynamoDB**
  - En qué microservicio: `____________________`
- [ ] Cada microservicio tiene **su propia base de datos**

---

## 13. Acceso único (SSO)

- [ ] La plataforma tiene **varias aplicaciones** (ej.: gestión, BI/dashboards, móvil)
  - Aplicaciones: `____________________`
- [ ] El usuario entra con **un solo login y un solo password**
- [ ] Se pasa de una aplicación a otra **sin volver a iniciar sesión**
  - Tecnología (ej.: Keycloak, OAuth2/OpenID Connect): `____________________`
- [ ] Hay al menos una app de **inteligencia de negocios** con dashboards generados con ML

---

## 14. Los 4 niveles de arquitectura

- [ ] **Arquitectura de backend** (diagrama de microservicios)
- [ ] **Arquitectura de frontend** (diagrama de los fronts, BFF/Gateway)
- [ ] **Arquitectura de datos**
  - [ ] Resuelve reportes frecuentes con datos de **varios microservicios** sin hacer JOIN entre bases
  - Mecanismo (ej.: CQRS, base de lectura consolidada, eventos): `____________________`
- [ ] **Arquitectura de despliegue** (contenedores, nube, servidores)
  - Tecnologías: `____________________`

---

## 15. Arquitecturas de código (las 3 obligatorias)

- [ ] **DDD (Domain-Driven Design)**
  - En qué microservicio: `____________________`
- [ ] **Arquitectura Hexagonal**
  - En qué microservicio: `____________________`
- [ ] **Clean Architecture**
  - En qué microservicio: `____________________`
- [ ] (Opcional) Otras arquitecturas aplicadas: `____________________`

---

## 16. Metodología

- [ ] El proyecto sigue la metodología **ICONIX**
  - [ ] Modelo de dominio
  - [ ] Casos de uso
  - [ ] Diagramas de robustez
  - [ ] Diagramas de secuencia
  - [ ] Diagrama de clases

---

## 📅 Entregas

- [ ] **Próxima clase:** documento **escrito y preliminar** que diga **dónde se aplica cada punto** de esta lista
- [ ] **Entrega final:** ~**12 de enero** *(confirmar la fecha con el ingeniero)*

---

## ❓ Cosas por confirmar con el ingeniero

- [ ] Qué significa "una especie de **fiel**" (¿BFF? ¿API Gateway?)
- [ ] Qué tecnología acepta para el **tercer frontend**
- [ ] Fecha exacta de la **entrega final**

---

### Resumen rápido

| # | Requisito | ¿Cumple? |
|---|-----------|:--------:|
| 1 | Microservicios: Spring Boot + NestJS + PHP | ⬜ |
| 2 | Frontends: Angular + React + 3.º (con móvil) | ⬜ |
| 3 | GraphQL en gestión + REST en el resto | ⬜ |
| 4 | Agentes inteligentes con skills | ⬜ |
| 5 | IA local (móvil y web) + offline + idempotencia | ⬜ |
| 6 | Transacción con 3+ microservicios (Saga) | ⬜ |
| 7 | ML supervisado + no supervisado + DL TensorFlow (imágenes/video) | ⬜ |
| 8 | Automatización con n8n | ⬜ |
| 9 | Reportes generativos (texto/voz → pantalla/Excel) | ⬜ |
| 10 | Protocolo MCP | ⬜ |
| 11 | Seguridad contra inyecciones | ⬜ |
| 12 | BD: Relacional (no MySQL) + MongoDB + DynamoDB | ⬜ |
| 13 | SSO (un solo login) | ⬜ |
| 14 | 4 arquitecturas: back, front, datos, despliegue | ⬜ |
| 15 | DDD + Hexagonal + Clean | ⬜ |
| 16 | Metodología ICONIX | ⬜ |
