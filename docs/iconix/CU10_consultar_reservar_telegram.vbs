'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU10 Consultar y reservar por Telegram
'
' Identificarse: POST /agentes/telegram/evento
' Consultar el menu: POST /agentes/telegram/evento
' Elegir turno, dia y plato: POST /agentes/telegram/evento
' Reservar (Saga 1): POST /agentes/telegram/evento
' Pago y confirmacion (hilo de MSIA, sin pasar por n8n)
' Solo el CAMINO EXITOSO (timeline limpio).
'
' Fragmentos que agregas a mano (EA no permite crearlos por script):
'   loop al elegir el turno y luego el dia: mensajes 54-68
'   alt sin beca que cubra hoy: mensajes 99-110
'   else beca que cubre hoy: mensajes 111-124
'
' USO:
' 1. Scripting -> Scripts -> tu grupo -> New VBScript
' 2. Pega TODO y Save Script
' 3. En el Browser SELECCIONA el paquete destino
' 4. Clic derecho sobre el script -> Run Script
'==================================================================

option explicit

!INC Local Scripts.EAConstants-VBScript

Dim oDiagram
Dim oPackage

' Indices de los participantes (de izquierda a derecha)
Const EST    = 0   ' Estudiante
Const TG     = 1   ' Vista (Telegram)
Const N8N    = 2   ' Automatizacion (n8n)
Const IA     = 3   ' AgentesRouter (MSIA)
Const SAGA   = 4   ' SagaOrchestrator (MSIA)
Const SQL    = 5   ' BD Agentes (SQLite)
Const DYNAMO = 6   ' BD Sagas (DynamoDB)
Const KC     = 7   ' Identidad (Keycloak)
Const MCPM   = 8   ' McpController (MSMenu)
Const POR    = 9   ' PorcionesController (MSMenu)
Const MONGO  = 10  ' BD Menu (MongoDB)
Const MCPR   = 11  ' McpController (MSReservas)
Const RES    = 12  ' ReservasController (MSReservas)
Const PGRES  = 13  ' BD Reservas (PostgreSQL)
Const PAG    = 14  ' PagosController (MSPagos)
Const PGPAG  = 15  ' BD Pagos (PostgreSQL)
Const STRIPE = 16  ' Pasarela (Stripe)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU10 - Secuencia Consultar y reservar por Telegram", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(16)
    nombres(EST)    = "Estudiante"
    nombres(TG)     = "Vista (Telegram)"
    nombres(N8N)    = "Automatizacion (n8n)"
    nombres(IA)     = "AgentesRouter (MSIA)"
    nombres(SAGA)   = "SagaOrchestrator (MSIA)"
    nombres(SQL)    = "BD Agentes (SQLite)"
    nombres(DYNAMO) = "BD Sagas (DynamoDB)"
    nombres(KC)     = "Identidad (Keycloak)"
    nombres(MCPM)   = "McpController (MSMenu)"
    nombres(POR)    = "PorcionesController (MSMenu)"
    nombres(MONGO)  = "BD Menu (MongoDB)"
    nombres(MCPR)   = "McpController (MSReservas)"
    nombres(RES)    = "ReservasController (MSReservas)"
    nombres(PGRES)  = "BD Reservas (PostgreSQL)"
    nombres(PAG)    = "PagosController (MSPagos)"
    nombres(PGPAG)  = "BD Pagos (PostgreSQL)"
    nombres(STRIPE) = "Pasarela (Stripe)"

    Dim els(16)
    Dim i
    For i = 0 To 16
        Dim el
        If i = EST Then
            Set el = oPackage.Elements.AddNew(nombres(i), "Actor")
        Else
            Set el = oPackage.Elements.AddNew(nombres(i), "Sequence")
        End If
        el.Update
        Set els(i) = el
    Next
    oPackage.Elements.Refresh

    ' ---------- Colocar los participantes en el diagrama ----------
    For i = 0 To 16
        Dim dobj
        Set dobj = oDiagram.DiagramObjects.AddNew("l=" & (40 + i * 215) & ";r=" & (210 + i * 215) & ";t=-20;b=-90", "")
        dobj.ElementID = els(i).ElementID
        dobj.Sequence = i + 1
        dobj.Update
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==============================================================
    ' Identificarse: POST /agentes/telegram/evento
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(EST),    els(TG),     1,   "/start"
    AddMsg els(N8N),    els(TG),     2,   "getUpdates(offset) (cada 10 segundos)"
    AddMsg els(TG),     els(N8N),    3,   "return(update)"
    AddMsg els(N8N),    els(IA),     4,   "telegram_evento(update)"
    AddMsg els(IA),     els(IA),     5,   "procesar_evento(update)"
    AddMsg els(IA),     els(SQL),    6,   "chat(cid)"
    AddMsg els(SQL),    els(IA),     7,   "return(sin vincular)"
    AddMsg els(IA),     els(IA),     8,   "_pedir_correo(cid)"
    AddMsg els(IA),     els(SQL),    9,   "guardar_chat(cid, pide_email)"
    AddMsg els(IA),     els(N8N),    10,  "return({ acciones: [sendMessage] })"
    AddMsg els(N8N),    els(TG),     11,  "sendMessage(chat, pide el correo)"
    AddMsg els(TG),     els(EST),    12,  "pide el correo institucional"
    AddMsg els(EST),    els(TG),     13,  "escribe su correo"
    AddMsg els(N8N),    els(TG),     14,  "getUpdates(offset)"
    AddMsg els(TG),     els(N8N),    15,  "return(update)"
    AddMsg els(N8N),    els(IA),     16,  "telegram_evento(update)"
    AddMsg els(IA),     els(IA),     17,  "procesar_evento(update)"
    AddMsg els(IA),     els(SQL),    18,  "chat(cid)"
    AddMsg els(SQL),    els(IA),     19,  "return(pide_email)"
    AddMsg els(IA),     els(IA),     20,  "_recibir_correo(cid, correo)"
    AddMsg els(IA),     els(KC),     21,  "usuario_por_email(correo)"
    AddMsg els(KC),     els(IA),     22,  "return({ username, nombre, roles })"
    AddMsg els(IA),     els(IA),     23,  "_vincular(cid, usuario)"
    AddMsg els(IA),     els(SQL),    24,  "guardar_chat(cid, listo, roles)"
    AddMsg els(IA),     els(N8N),    25,  "return({ acciones: [sendMessage] })"
    AddMsg els(N8N),    els(TG),     26,  "sendMessage(chat, menu principal con botones)"
    AddMsg els(TG),     els(EST),    27,  "muestra Menu, Quien soy y Reservar"
    ' ==============================================================
    ' Consultar el menu: POST /agentes/telegram/evento
    ' ==============================================================
    AddMsg els(EST),    els(TG),     28,  "pulsa 'Menu'"
    AddMsg els(N8N),    els(TG),     29,  "getUpdates(offset)"
    AddMsg els(TG),     els(N8N),    30,  "return(update)"
    AddMsg els(N8N),    els(IA),     31,  "telegram_evento(update)"
    AddMsg els(IA),     els(IA),     32,  "procesar_evento(update)"
    AddMsg els(IA),     els(SQL),    33,  "chat(cid)"
    AddMsg els(SQL),    els(IA),     34,  "return(listo)"
    AddMsg els(IA),     els(IA),     35,  "_ver_menu(cid, turno)"
    AddMsg els(IA),     els(MCPM),   36,  "MCP tools/call consultar_menu(turno)"
    AddMsg els(MCPM),   els(MONGO),  37,  "findBySemana(inicio, turno)"
    AddMsg els(MONGO),  els(MCPM),   38,  "return(menus)"
    AddMsg els(MCPM),   els(IA),     39,  "return(menus con porciones disponibles)"
    AddMsg els(IA),     els(N8N),    40,  "return({ acciones: [answerCallbackQuery, sendMessage] })"
    AddMsg els(N8N),    els(TG),     41,  "sendMessage(chat, menu por dia)"
    AddMsg els(TG),     els(EST),    42,  "muestra el menu y los cupos"
    ' ==============================================================
    ' Elegir turno, dia y plato: POST /agentes/telegram/evento
    ' ==============================================================
    AddMsg els(EST),    els(TG),     43,  "pulsa 'Reservar'"
    AddMsg els(N8N),    els(TG),     44,  "getUpdates(offset)"
    AddMsg els(TG),     els(N8N),    45,  "return(update)"
    AddMsg els(N8N),    els(IA),     46,  "telegram_evento(update)"
    AddMsg els(IA),     els(IA),     47,  "procesar_evento(update)"
    AddMsg els(IA),     els(SQL),    48,  "chat(cid)"
    AddMsg els(SQL),    els(IA),     49,  "return(listo)"
    AddMsg els(IA),     els(IA),     50,  "_elegir_turno(cid, chat)"
    AddMsg els(IA),     els(N8N),    51,  "return({ acciones: [answerCallbackQuery, sendMessage] })"
    AddMsg els(N8N),    els(TG),     52,  "sendMessage(chat, botones de turno)"
    AddMsg els(TG),     els(EST),    53,  "muestra los turnos"
    ' loop al elegir el turno y luego el dia (mensajes 54 a 68)
    AddMsg els(EST),    els(TG),     54,  "pulsa una opcion"
    AddMsg els(N8N),    els(TG),     55,  "getUpdates(offset)"
    AddMsg els(TG),     els(N8N),    56,  "return(update)"
    AddMsg els(N8N),    els(IA),     57,  "telegram_evento(update)"
    AddMsg els(IA),     els(IA),     58,  "procesar_evento(update)"
    AddMsg els(IA),     els(SQL),    59,  "chat(cid)"
    AddMsg els(SQL),    els(IA),     60,  "return(listo)"
    AddMsg els(IA),     els(IA),     61,  "_elegir_dia(turno) o _elegir_plato(turno, fecha)"
    AddMsg els(IA),     els(MCPM),   62,  "MCP tools/call consultar_menu(turno)"
    AddMsg els(MCPM),   els(MONGO),  63,  "findBySemana(inicio, turno)"
    AddMsg els(MONGO),  els(MCPM),   64,  "return(menus)"
    AddMsg els(MCPM),   els(IA),     65,  "return(menus con porciones disponibles)"
    AddMsg els(IA),     els(N8N),    66,  "return({ acciones: [answerCallbackQuery, sendMessage] })"
    AddMsg els(N8N),    els(TG),     67,  "sendMessage(chat, botones de dia o de plato)"
    AddMsg els(TG),     els(EST),    68,  "muestra los dias o los platos con cupo"
    ' ==============================================================
    ' Reservar (Saga 1): POST /agentes/telegram/evento
    ' ==============================================================
    AddMsg els(EST),    els(TG),     69,  "pulsa un plato"
    AddMsg els(N8N),    els(TG),     70,  "getUpdates(offset)"
    AddMsg els(TG),     els(N8N),    71,  "return(update)"
    AddMsg els(N8N),    els(IA),     72,  "telegram_evento(update)"
    AddMsg els(IA),     els(IA),     73,  "procesar_evento(update)"
    AddMsg els(IA),     els(SQL),    74,  "chat(cid)"
    AddMsg els(SQL),    els(IA),     75,  "return(listo)"
    AddMsg els(IA),     els(IA),     76,  "_reservar(cid, chat, turno, fecha, plato)"
    AddMsg els(IA),     els(MCPM),   77,  "MCP tools/call consultar_menu(turno)"
    AddMsg els(MCPM),   els(MONGO),  78,  "findBySemana(inicio, turno)"
    AddMsg els(MONGO),  els(MCPM),   79,  "return(menus)"
    AddMsg els(MCPM),   els(IA),     80,  "return(menu con cupo)"
    AddMsg els(IA),     els(MCPR),   81,  "MCP tools/call consultar_beca(estudianteId)"
    AddMsg els(MCPR),   els(PGRES),  82,  "findActivaByEstudiante(id)"
    AddMsg els(PGRES),  els(MCPR),   83,  "return(beca)"
    AddMsg els(MCPR),   els(IA),     84,  "return({ tieneBeca, cubreHoy })"
    AddMsg els(IA),     els(SAGA),   85,  "reservar_y_pagar(dto)"
    AddMsg els(SAGA),   els(DYNAMO), 86,  "check_and_lock_idempotency(key)"
    AddMsg els(DYNAMO), els(SAGA),   87,  "return(clave nueva)"
    AddMsg els(SAGA),   els(DYNAMO), 88,  "put_saga(sagaId, RUNNING)"
    AddMsg els(SAGA),   els(RES),    89,  "crear(dto)"
    AddMsg els(RES),    els(RES),    90,  "ReservarRacionUseCase.execute(dto)"
    AddMsg els(RES),    els(PGRES),  91,  "save(reserva 'pendiente')"
    AddMsg els(PGRES),  els(RES),    92,  "return(reserva)"
    AddMsg els(RES),    els(SAGA),   93,  "return({ id, estado: 'pendiente' })"
    AddMsg els(SAGA),   els(POR),    94,  "apartar(dto)"
    AddMsg els(POR),    els(POR),    95,  "ApartarPorcionUseCase.ejecutar(dto)"
    AddMsg els(POR),    els(MONGO),  96,  "save(menu, apartadas + 1)"
    AddMsg els(MONGO),  els(POR),    97,  "return(menu)"
    AddMsg els(POR),    els(SAGA),   98,  "return({ ok: true })"
    ' alt sin beca que cubra hoy (mensajes 99 a 110)
    AddMsg els(SAGA),   els(PAG),    99,  "cobrar(dto, qr_bancario)"
    AddMsg els(PAG),    els(PAG),    100, "CobrarRacionService.execute(dto)"
    AddMsg els(PAG),    els(STRIPE), 101, "cobrarQr(monto, pagoId)"
    AddMsg els(STRIPE), els(PAG),    102, "return({ paymentUrl, referencia })"
    AddMsg els(PAG),    els(PGPAG),  103, "save(pago) / save(ticket)"
    AddMsg els(PGPAG),  els(PAG),    104, "return(ok)"
    AddMsg els(PAG),    els(SAGA),   105, "return({ pagoId, ticketId, stripe })"
    AddMsg els(SAGA),   els(DYNAMO), 106, "put_saga(sagaId, PENDING_PAYMENT)"
    AddMsg els(SAGA),   els(IA),     107, "return({ status: PENDING_PAYMENT, reservaId, stripe })"
    AddMsg els(IA),     els(SQL),    108, "guardar_pago(reservaId, chat, referencia, plato, fecha, turno)"
    AddMsg els(IA),     els(N8N),    109, "POST /webhook/notificar-foto(chat, QR de pago)"
    AddMsg els(N8N),    els(TG),     110, "sendPhoto(chat, QR de pago)"
    ' else beca que cubre hoy (mensajes 111 a 124)
    AddMsg els(SAGA),   els(PAG),    111, "cobrar(dto, beca)"
    AddMsg els(PAG),    els(PAG),    112, "CobrarRacionService.execute(dto)"
    AddMsg els(PAG),    els(PGPAG),  113, "save(pago) / save(ticket)"
    AddMsg els(PGPAG),  els(PAG),    114, "return(ok)"
    AddMsg els(PAG),    els(SAGA),   115, "return({ pagoId, ticketId })"
    AddMsg els(SAGA),   els(RES),    116, "confirmarR(reservaId)"
    AddMsg els(RES),    els(RES),    117, "ConfirmarReservaUseCase.execute(reservaId)"
    AddMsg els(RES),    els(PGRES),  118, "save(reserva 'confirmada')"
    AddMsg els(PGRES),  els(RES),    119, "return(reserva)"
    AddMsg els(RES),    els(SAGA),   120, "return({ reservaId, qr })"
    AddMsg els(SAGA),   els(DYNAMO), 121, "put_saga(sagaId, COMPLETED)"
    AddMsg els(SAGA),   els(IA),     122, "return({ status: COMPLETED, reservaId, qr })"
    AddMsg els(IA),     els(N8N),    123, "POST /webhook/notificar-foto(chat, QR de ingreso)"
    AddMsg els(N8N),    els(TG),     124, "sendPhoto(chat, QR de ingreso)"
    AddMsg els(IA),     els(N8N),    125, "return({ acciones: [answerCallbackQuery, sendMessage] })"
    AddMsg els(N8N),    els(TG),     126, "sendMessage(chat, reserva creada o confirmada)"
    AddMsg els(TG),     els(EST),    127, "muestra la reserva y su QR"
    ' ==============================================================
    ' Pago y confirmacion (hilo de MSIA, sin pasar por n8n)
    ' ==============================================================
    AddMsg els(EST),    els(STRIPE), 128, "paga con el QR o el enlace"
    AddMsg els(STRIPE), els(EST),    129, "pago aprobado"
    AddMsg els(IA),     els(IA),     130, "bucle_pagos() (cada 8 segundos)"
    AddMsg els(IA),     els(SQL),    131, "pagos_en_curso()"
    AddMsg els(SQL),    els(IA),     132, "return(pagos esperando confirmacion)"
    AddMsg els(IA),     els(IA),     133, "_verificar_pago(reservaId)"
    AddMsg els(IA),     els(SAGA),   134, "confirmar_pago(reservaId, referencia)"
    AddMsg els(SAGA),   els(PAG),    135, "verificar(referencia)"
    AddMsg els(PAG),    els(STRIPE), 136, "verificarPago(referencia)"
    AddMsg els(STRIPE), els(PAG),    137, "return({ paid: true })"
    AddMsg els(PAG),    els(SAGA),   138, "return({ paid: true })"
    AddMsg els(SAGA),   els(RES),    139, "confirmarR(reservaId)"
    AddMsg els(RES),    els(RES),    140, "ConfirmarReservaUseCase.execute(reservaId)"
    AddMsg els(RES),    els(PGRES),  141, "save(reserva 'confirmada')"
    AddMsg els(PGRES),  els(RES),    142, "return(reserva)"
    AddMsg els(RES),    els(SAGA),   143, "return({ reservaId, qr })"
    AddMsg els(SAGA),   els(IA),     144, "return({ confirmada: true, qr })"
    AddMsg els(IA),     els(SQL),    145, "marcar_pago(reservaId, esperando_factura)"
    AddMsg els(IA),     els(N8N),    146, "POST /webhook/notificar(telegram, pago recibido)"
    AddMsg els(N8N),    els(TG),     147, "sendMessage(chat, pago recibido)"
    AddMsg els(IA),     els(N8N),    148, "POST /webhook/notificar-foto(chat, QR de ingreso)"
    AddMsg els(N8N),    els(TG),     149, "sendPhoto(chat, QR de ingreso)"
    AddMsg els(IA),     els(IA),     150, "_enviar_factura(pago)"
    AddMsg els(IA),     els(PAG),    151, "recibo(referencia)"
    AddMsg els(PAG),    els(STRIPE), 152, "facturaUrl(referencia)"
    AddMsg els(STRIPE), els(PAG),    153, "return({ url, tipo, pdf })"
    AddMsg els(PAG),    els(IA),     154, "return({ url, tipo, pdf })"
    AddMsg els(IA),     els(N8N),    155, "POST /webhook/notificar(telegram, enlace de la factura)"
    AddMsg els(N8N),    els(TG),     156, "sendMessage(chat, enlace de la factura)"
    AddMsg els(IA),     els(SQL),    157, "marcar_pago(reservaId, completado)"
    AddMsg els(TG),     els(EST),    158, "muestra la confirmacion, el QR de ingreso y la factura"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU10 creado (camino exitoso, 158 mensajes)." & vbCrLf & _
                   "Agrega a mano: loop al elegir el turno y luego el dia: mensajes 54-68; alt sin beca que cubra hoy: mensajes 99-110; else beca que cubre hoy: mensajes 111-124.", 0

End Sub

'------------------------------------------------------------------
' Crea un mensaje (connector Sequence) entre dos elementos
'   origen = destino -> mensaje reflexivo (auto-llamada)
'------------------------------------------------------------------
Sub AddMsg(oOrigen, oDestino, nNum, sTexto)
    Dim con
    Set con = oOrigen.Connectors.AddNew(sTexto, "Sequence")
    con.SupplierID = oDestino.ElementID
    con.SequenceNo = nNum
    con.Update
    oOrigen.Connectors.Refresh
End Sub

Main
