'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE COMUNICACION (COLABORACION) - CU10 Consultar y reservar por Telegram
'
' Grupo 0: identificarse           (POST /agentes/telegram/evento)
' Grupo 1: consultar el menu       (POST /agentes/telegram/evento)
' Grupo 2: reservar (Saga 1)       (POST /agentes/telegram/evento)
' Grupo 3: pago y confirmacion     (hilo de MSIA, sin pasar por n8n)
' Los participantes se unen con una ASOCIACION y los mensajes van sobre
' esa asociacion (lo mismo que hacer a mano "Add Message from A to B").
' El mensaje lleva solo el nombre: el numero y la flechita los pone EA.
' Version RESUMIDA del diagrama de secuencia CU10:
'   - sin las llamadas a si mismo
'   - el paso "elegir turno, dia y plato" (loop) no se repite: es otro consultar_menu
'   - de la reserva se dibuja la rama "sin beca" (cobro por QR); la rama con beca no
'   - no se dibuja el pago del estudiante en Stripe ni el envio de la factura
'
' USO:
' 1. Scripting -> Scripts -> tu grupo -> New VBScript
' 2. Pega TODO y Save Script
' 3. En el Browser SELECCIONA el paquete destino (vacio)
' 4. Clic derecho sobre el script -> Run Script
'==================================================================

option explicit

!INC Local Scripts.EAConstants-VBScript

Dim oDiagram
Dim oPackage
Dim nMsg             ' orden global de los mensajes (SequenceNo)
Dim nGrupo           ' grupo actual: un grupo por endpoint (0, 1, 2...)
Dim nEnGrupo         ' numero del mensaje dentro del grupo
Dim oAsoc            ' ConnectorID de la asociacion de cada par de participantes
Dim oCuenta          ' cuantos mensajes hay ya en cada lado de cada asociacion

' Indices de los participantes
Const EST    = 0   ' Estudiante                      (actor)
Const TG     = 1   ' Vista (Telegram)                (boundary)
Const N8N    = 2   ' Automatizacion (n8n)            (control)
Const IA     = 3   ' AgentesRouter (MSIA)            (control)
Const SQL    = 4   ' BD Agentes (SQLite)             (entity)
Const KC     = 5   ' Identidad (Keycloak)            (boundary)
Const MCPM   = 6   ' McpController (MSMenu)          (control)
Const MONGO  = 7   ' BD Menu (MongoDB)               (entity)
Const MCPR   = 8   ' McpController (MSReservas)      (control)
Const SAGA   = 9   ' SagaOrchestrator (MSIA)         (control)
Const DYNAMO = 10  ' BD Sagas (DynamoDB)             (entity)
Const RES    = 11  ' ReservasController (MSReservas) (control)
Const PGRES  = 12  ' BD Reservas (PostgreSQL)        (entity)
Const POR    = 13  ' PorcionesController (MSMenu)    (control)
Const PAG    = 14  ' PagosController (MSPagos)       (control)
Const PGPAG  = 15  ' BD Pagos (PostgreSQL)           (entity)
Const STRIPE = 16  ' Pasarela (Stripe)               (boundary)
Const ULTIMO = 16

Dim els(16)          ' elementos creados
Dim cx(16), cy(16)   ' centro de cada participante en el diagrama

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Comunicacion ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU10 - Comunicacion Consultar y reservar por Telegram", "Collaboration")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Participantes: nombre y figura ----------
    Dim nombres(16), figuras(16)
    nombres(EST)    = "Estudiante":                        figuras(EST)    = "actor"
    nombres(TG)     = "Vista (Telegram)":                  figuras(TG)     = "boundary"
    nombres(N8N)    = "Automatizacion (n8n)":              figuras(N8N)    = "control"
    nombres(IA)     = "AgentesRouter (MSIA)":              figuras(IA)     = "control"
    nombres(SQL)    = "BD Agentes (SQLite)":               figuras(SQL)    = "entity"
    nombres(KC)     = "Identidad (Keycloak)":              figuras(KC)     = "boundary"
    nombres(MCPM)   = "McpController (MSMenu)":            figuras(MCPM)   = "control"
    nombres(MONGO)  = "BD Menu (MongoDB)":                 figuras(MONGO)  = "entity"
    nombres(MCPR)   = "McpController (MSReservas)":        figuras(MCPR)   = "control"
    nombres(SAGA)   = "SagaOrchestrator (MSIA)":           figuras(SAGA)   = "control"
    nombres(DYNAMO) = "BD Sagas (DynamoDB)":               figuras(DYNAMO) = "entity"
    nombres(RES)    = "ReservasController (MSReservas)":   figuras(RES)    = "control"
    nombres(PGRES)  = "BD Reservas (PostgreSQL)":          figuras(PGRES)  = "entity"
    nombres(POR)    = "PorcionesController (MSMenu)":      figuras(POR)    = "control"
    nombres(PAG)    = "PagosController (MSPagos)":         figuras(PAG)    = "control"
    nombres(PGPAG)  = "BD Pagos (PostgreSQL)":             figuras(PGPAG)  = "entity"
    nombres(STRIPE) = "Pasarela (Stripe)":                 figuras(STRIPE) = "boundary"

    ' ---------- Posiciones: l, r, t, b (t y b negativos en EA) ----------
    ' Fila 1: estudiante y Telegram; SQLite y Keycloak arriba del agente; McpReservas y su BD a la derecha
    ' Fila 2: n8n bajo Telegram -> agente -> saga -> reservas -> (BD reservas arriba)
    ' Fila 3: McpMenu y Mongo bajo el agente; porciones (comparte Mongo); Dynamo bajo la saga; pagos y su BD
    ' Fila 4: Stripe bajo pagos
    Dim pos(16)
    pos(EST)    = Array(40, 90, -200, -270)
    pos(TG)     = Array(400, 490, -200, -270)
    pos(SQL)    = Array(1000, 1090, -200, -270)
    pos(KC)     = Array(1400, 1490, -200, -270)
    pos(MCPR)   = Array(2800, 2890, -400, -470)
    pos(N8N)    = Array(400, 490, -760, -830)
    pos(IA)     = Array(1000, 1090, -760, -830)
    pos(SAGA)   = Array(1800, 1890, -760, -830)
    pos(RES)    = Array(2400, 2490, -760, -830)
    pos(PGRES)  = Array(2800, 2890, -760, -830)
    pos(MCPM)   = Array(1000, 1090, -1120, -1190)
    pos(MONGO)  = Array(1400, 1490, -1120, -1190)
    pos(POR)    = Array(1800, 1890, -1120, -1190)
    pos(DYNAMO) = Array(2100, 2190, -1120, -1190)
    pos(PAG)    = Array(2400, 2490, -1120, -1190)
    pos(PGPAG)  = Array(2800, 2890, -1120, -1190)
    pos(STRIPE) = Array(2400, 2490, -1480, -1550)

    Dim i
    For i = 0 To ULTIMO
        Set els(i) = NuevoParticipante(nombres(i), figuras(i))
        AddObj els(i), pos(i), i + 1
        cx(i) = (pos(i)(0) + pos(i)(1)) / 2
        cy(i) = (pos(i)(2) + pos(i)(3)) / 2
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==============================================================
    ' 1) Asociaciones: la linea que une a los participantes
    ' ==============================================================
    Set oAsoc = CreateObject("Scripting.Dictionary")
    AddAsoc EST,    TG
    AddAsoc TG,     N8N
    AddAsoc N8N,    IA
    AddAsoc IA,     SQL
    AddAsoc IA,     KC
    AddAsoc IA,     MCPM
    AddAsoc MCPM,   MONGO
    AddAsoc IA,     MCPR
    AddAsoc MCPR,   PGRES
    AddAsoc IA,     SAGA
    AddAsoc SAGA,   DYNAMO
    AddAsoc SAGA,   RES
    AddAsoc RES,    PGRES
    AddAsoc SAGA,   POR
    AddAsoc POR,    MONGO
    AddAsoc SAGA,   PAG
    AddAsoc PAG,    PGPAG
    AddAsoc PAG,    STRIPE

    ' ==============================================================
    ' 2) Mensajes sobre cada asociacion, en orden (ida y vuelta)
    '    AddMsg origen, destino, texto      (el numero lo pone el script)
    ' ==============================================================
    nMsg = 0
    nGrupo = -1
    Set oCuenta = CreateObject("Scripting.Dictionary")

    ' ---- Grupo 0: identificarse ----
    NuevoGrupo
    AddMsg EST,  TG,   "start()"
    AddMsg N8N,  TG,   "getUpdates(offset)"
    AddMsg TG,   N8N,  "return(update)"
    AddMsg N8N,  IA,   "telegram_evento(update)"
    AddMsg IA,   SQL,  "chat(cid)"
    AddMsg SQL,  IA,   "return(sin vincular)"
    AddMsg IA,   SQL,  "guardar_chat(cid, pide_email)"
    AddMsg IA,   N8N,  "return(acciones sendMessage)"
    AddMsg N8N,  TG,   "sendMessage(chat, pide el correo)"
    AddMsg TG,   EST,  "mostrar(pide el correo institucional)"
    AddMsg EST,  TG,   "escribir(correo)"
    AddMsg N8N,  TG,   "getUpdates(offset)"
    AddMsg TG,   N8N,  "return(update)"
    AddMsg N8N,  IA,   "telegram_evento(update)"
    AddMsg IA,   SQL,  "chat(cid)"
    AddMsg SQL,  IA,   "return(pide_email)"
    AddMsg IA,   KC,   "usuario_por_email(correo)"
    AddMsg KC,   IA,   "return(username, nombre, roles)"
    AddMsg IA,   SQL,  "guardar_chat(cid, listo, roles)"
    AddMsg IA,   N8N,  "return(acciones sendMessage)"
    AddMsg N8N,  TG,   "sendMessage(chat, menu principal con botones)"
    AddMsg TG,   EST,  "mostrar(Menu, Quien soy y Reservar)"

    ' ---- Grupo 1: consultar el menu ----
    NuevoGrupo
    AddMsg EST,   TG,    "pulsar(Menu)"
    AddMsg N8N,   TG,    "getUpdates(offset)"
    AddMsg TG,    N8N,   "return(update)"
    AddMsg N8N,   IA,    "telegram_evento(update)"
    AddMsg IA,    SQL,   "chat(cid)"
    AddMsg SQL,   IA,    "return(listo)"
    AddMsg IA,    MCPM,  "consultar_menu(turno)"
    AddMsg MCPM,  MONGO, "findBySemana(inicio, turno)"
    AddMsg MONGO, MCPM,  "return(menus)"
    AddMsg MCPM,  IA,    "return(menus con porciones disponibles)"
    AddMsg IA,    N8N,   "return(acciones answerCallbackQuery, sendMessage)"
    AddMsg N8N,   TG,    "sendMessage(chat, menu por dia)"
    AddMsg TG,    EST,   "mostrar(menu y cupos)"

    ' ---- Grupo 2: reservar (Saga 1), rama sin beca ----
    NuevoGrupo
    AddMsg EST,    TG,     "pulsar(plato)"
    AddMsg N8N,    TG,     "getUpdates(offset)"
    AddMsg TG,     N8N,    "return(update)"
    AddMsg N8N,    IA,     "telegram_evento(update)"
    AddMsg IA,     SQL,    "chat(cid)"
    AddMsg SQL,    IA,     "return(listo)"
    AddMsg IA,     MCPM,   "consultar_menu(turno)"
    AddMsg MCPM,   MONGO,  "findBySemana(inicio, turno)"
    AddMsg MONGO,  MCPM,   "return(menus)"
    AddMsg MCPM,   IA,     "return(menu con cupo)"
    AddMsg IA,     MCPR,   "consultar_beca(estudianteId)"
    AddMsg MCPR,   PGRES,  "findActivaByEstudiante(id)"
    AddMsg PGRES,  MCPR,   "return(beca)"
    AddMsg MCPR,   IA,     "return(tieneBeca, cubreHoy)"
    AddMsg IA,     SAGA,   "reservar_y_pagar(dto)"
    AddMsg SAGA,   DYNAMO, "bloquear_idempotencia(key)"
    AddMsg DYNAMO, SAGA,   "return(clave nueva)"
    AddMsg SAGA,   DYNAMO, "guardar_saga(sagaId, RUNNING)"
    AddMsg SAGA,   RES,    "crear(dto)"
    AddMsg RES,    PGRES,  "save(reserva pendiente)"
    AddMsg PGRES,  RES,    "return(reserva)"
    AddMsg RES,    SAGA,   "return(id, pendiente)"
    AddMsg SAGA,   POR,    "apartar(dto)"
    AddMsg POR,    MONGO,  "save(menu, apartadas + 1)"
    AddMsg MONGO,  POR,    "return(menu)"
    AddMsg POR,    SAGA,   "return(ok)"
    AddMsg SAGA,   PAG,    "cobrar(dto, qr_bancario)"
    AddMsg PAG,    STRIPE, "cobrarQr(monto, pagoId)"
    AddMsg STRIPE, PAG,    "return(paymentUrl, referencia)"
    AddMsg PAG,    PGPAG,  "save(pago, ticket)"
    AddMsg PGPAG,  PAG,    "return(ok)"
    AddMsg PAG,    SAGA,   "return(pagoId, ticketId, stripe)"
    AddMsg SAGA,   DYNAMO, "guardar_saga(sagaId, PENDING_PAYMENT)"
    AddMsg SAGA,   IA,     "return(PENDING_PAYMENT, reservaId, stripe)"
    AddMsg IA,     SQL,    "guardar_pago(reservaId, chat, referencia, plato, fecha, turno)"
    AddMsg IA,     N8N,    "notificarFoto(chat, QR de pago)"
    AddMsg N8N,    TG,     "sendPhoto(chat, QR de pago)"
    AddMsg IA,     N8N,    "return(acciones answerCallbackQuery, sendMessage)"
    AddMsg N8N,    TG,     "sendMessage(chat, reserva creada)"
    AddMsg TG,     EST,    "mostrar(reserva y QR de pago)"

    ' ---- Grupo 3: pago y confirmacion (hilo de MSIA, sin pasar por n8n) ----
    NuevoGrupo
    AddMsg IA,     SQL,    "pagos_en_curso()"
    AddMsg SQL,    IA,     "return(pagos esperando confirmacion)"
    AddMsg IA,     SAGA,   "confirmar_pago(reservaId, referencia)"
    AddMsg SAGA,   PAG,    "verificar(referencia)"
    AddMsg PAG,    STRIPE, "verificarPago(referencia)"
    AddMsg STRIPE, PAG,    "return(paid true)"
    AddMsg PAG,    SAGA,   "return(paid true)"
    AddMsg SAGA,   RES,    "confirmarR(reservaId)"
    AddMsg RES,    PGRES,  "save(reserva confirmada)"
    AddMsg PGRES,  RES,    "return(reserva)"
    AddMsg RES,    SAGA,   "return(reservaId, qr)"
    AddMsg SAGA,   IA,     "return(confirmada, qr)"
    AddMsg IA,     SQL,    "marcar_pago(reservaId, completado)"
    AddMsg IA,     N8N,    "notificar(telegram, pago recibido)"
    AddMsg N8N,    TG,     "sendMessage(chat, pago recibido)"
    AddMsg IA,     N8N,    "notificarFoto(chat, QR de ingreso)"
    AddMsg N8N,    TG,     "sendPhoto(chat, QR de ingreso)"
    AddMsg TG,     EST,    "mostrar(confirmacion y QR de ingreso)"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama de comunicacion CU10 creado (18 asociaciones, " & nMsg & " mensajes).", 0

End Sub

'------------------------------------------------------------------
' Crea un participante: actor, o un objeto boundary/control/entity
'------------------------------------------------------------------
Function NuevoParticipante(sNombre, sFigura)
    Dim el
    If sFigura = "actor" Then
        Set el = oPackage.Elements.AddNew(sNombre, "Actor")
    Else
        Set el = oPackage.Elements.AddNew(sNombre, "Object")
        el.Stereotype = sFigura
    End If
    el.Update
    oPackage.Elements.Refresh
    Set NuevoParticipante = el
End Function

'------------------------------------------------------------------
' Coloca un participante en el diagrama
'------------------------------------------------------------------
Sub AddObj(oElem, aPos, nSeq)
    Dim dobj
    Set dobj = oDiagram.DiagramObjects.AddNew("l=" & aPos(0) & ";r=" & aPos(1) & ";t=" & aPos(2) & ";b=" & aPos(3) & ";", "")
    dobj.ElementID = oElem.ElementID
    dobj.Sequence = nSeq
    dobj.Update
End Sub

'------------------------------------------------------------------
' Clave de un par de participantes (siempre indice menor - mayor)
'------------------------------------------------------------------
Function ClavePar(iA, iB)
    If iA < iB Then
        ClavePar = iA & "-" & iB
    Else
        ClavePar = iB & "-" & iA
    End If
End Function

'------------------------------------------------------------------
' Asociacion simple (linea sin flecha) entre dos participantes.
' Guarda su ConnectorID: los mensajes lo necesitan para colgarse de ella.
'------------------------------------------------------------------
Sub AddAsoc(iA, iB)
    Dim con
    Set con = els(iA).Connectors.AddNew("", "Association")
    con.SupplierID = els(iB).ElementID
    con.Direction = "Unspecified"
    con.Update
    els(iA).Connectors.Refresh
    oAsoc(ClavePar(iA, iB)) = con.ConnectorID
End Sub

'------------------------------------------------------------------
' Empieza un grupo nuevo de mensajes (uno por endpoint).
' El numero que se ve es grupo.mensaje: 0.1, 0.2 ... y luego 1.1, 1.2 ...
'------------------------------------------------------------------
Sub NuevoGrupo()
    nGrupo = nGrupo + 1
    nEnGrupo = 0
End Sub

'------------------------------------------------------------------
' Mensaje de comunicacion de origen a destino, colgado de su asociacion.
'   Solo el nombre. El numero (grupo.mensaje) se guarda en PDATA4, que es
'   donde EA tiene el numero que muestra; el orden global va en SequenceNo.
'   Se guarda igual que cuando se hace a mano "Add Message from A to B".
'   Lo que hace que EA lo dibuje SOBRE la asociacion y con su flechita
'   es SourceIsAggregate = ConnectorID de la asociacion; ese campo no
'   se puede escribir por la API, asi que va con un UPDATE.
'------------------------------------------------------------------
Sub AddMsg(iOrigen, iDestino, sTexto)
    Dim con, geo, dl, sql

    If Not oAsoc.Exists(ClavePar(iOrigen, iDestino)) Then
        Session.Prompt "Falta la asociacion para el mensaje: " & sTexto, 0
        Exit Sub
    End If

    nMsg = nMsg + 1
    nEnGrupo = nEnGrupo + 1
    Set con = els(iOrigen).Connectors.AddNew(sTexto, "Collaboration")
    con.SupplierID = els(iDestino).ElementID
    con.DiagramID = oDiagram.DiagramID
    con.SequenceNo = nMsg
    con.Direction = "Source -> Destination"
    con.TransitionEvent = "Synchronous"
    con.TransitionAction = "Call"
    If Left(sTexto, 7) = "return(" Then
        con.StateFlags = "IsReturn=true;"
    Else
        con.StateFlags = "IsReturn=false;"
    End If
    con.Update
    con.SupplierEnd.IsNavigable = True
    con.SupplierEnd.Update
    els(iOrigen).Connectors.Refresh

    ' Posicion del texto y la flechita respecto del medio de la asociacion
    geo = GeoMensaje(iOrigen, iDestino)

    ' Mismos valores que deja EA en un mensaje hecho a mano
    sql = "UPDATE t_connector SET " & _
          "SourceIsAggregate=" & oAsoc(ClavePar(iOrigen, iDestino)) & ", " & _
          "SourceContainment='Unspecified', DestContainment='Unspecified', " & _
          "RouteStyle=3, Start_Edge=0, End_Edge=0, " & _
          "PtStartX=0, PtStartY=0, PtEndX=0, PtEndY=0, " & _
          "SourceChangeable='none', DestChangeable='none', " & _
          "SourceTS='instance', DestTS='instance', " & _
          "SourceStyle='Union=0;Derived=0;AllowDuplicates=0;Owned=0;Navigable=Non-Navigable;', " & _
          "DestStyle='Union=0;Derived=0;AllowDuplicates=0;Owned=0;Navigable=Navigable;', " & _
          "PDATA4='" & nGrupo & "." & nEnGrupo & "', " & _
          "PDATA5='" & geo & "' " & _
          "WHERE Connector_ID=" & con.ConnectorID
    Repository.Execute sql

    ' El mismo dato en el diagrama
    Set dl = oDiagram.DiagramLinks.AddNew("", "")
    dl.ConnectorID = con.ConnectorID
    dl.Geometry = geo & "$LLB=;LLT=;LMT=;LMB=;LRT=;LRB=;IRHS=;ILHS=;"
    dl.Update
    oDiagram.DiagramLinks.Refresh
End Sub

'------------------------------------------------------------------
' Donde va el texto del mensaje (con su flechita al final), medido
' desde el medio de la asociacion. Y positivo = arriba.
' A mano EA guarda SX=0;SY=31;EX=30;EY=31 (EX = SX + 30, EY = SY).
'   - asociacion horizontal: la ida arriba de la linea, la vuelta abajo
'   - asociacion vertical:   la ida a la derecha, la vuelta a la izquierda
'   - varios mensajes del mismo lado se apilan
'------------------------------------------------------------------
Function GeoMensaje(iOrigen, iDestino)
    Dim a, b, sentido, dx, dy, clave, n, ox, oy, borde

    ' La asociacion se mira siempre en el mismo orden (indice menor -> mayor)
    If iOrigen < iDestino Then
        a = iOrigen: b = iDestino: sentido = 1
    Else
        a = iDestino: b = iOrigen: sentido = -1
    End If
    dx = cx(b) - cx(a)
    dy = cy(b) - cy(a)

    ' Cuantos mensajes hay ya de este lado de esta asociacion
    clave = a & "-" & b & "|" & sentido
    n = 0
    If oCuenta.Exists(clave) Then n = oCuenta(clave)
    oCuenta(clave) = n + 1

    If Abs(dx) >= Abs(dy) Then
        ' horizontal
        ox = 40
        oy = sentido * (31 + 24 * n)
        If sentido * dx > 0 Then borde = 2 Else borde = 4
    Else
        ' vertical
        If sentido > 0 Then ox = 160 Else ox = -45
        oy = 12 - 24 * n
        If sentido * dy > 0 Then borde = 1 Else borde = 3
    End If

    GeoMensaje = "SX=" & ox & ";SY=" & oy & ";EX=" & (ox + 30) & ";EY=" & oy & ";EDGE=" & borde & ";"
End Function

Main
