'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU01 Reservar y pagar una racion
' Flujo: Vista -> Gateway -> Orquestador (Saga) -> microservicios -> BD
'
' Dos endpoints: POST /sagas/reservar y POST /sagas/pagar
' Solo el CAMINO EXITOSO (timeline limpio).
' Las ramas alternativas (becario que no paga, reserva no pendiente,
' cobro fallido) van DENTRO de los fragmentos 'alt' que agregas a mano
' (EA no permite crear 'alt' por script).
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
Const VISTA  = 1   ' Frontend React
Const GW     = 2   ' Gateway REST (este CU no usa GraphQL: solo lo usa el back-office)
Const SAGA   = 3   ' MSIA
Const DYNAMO = 4   ' BD de MSIA
Const RES    = 5   ' MSReservas
Const PGRES  = 6   ' BD de MSReservas
Const MENU   = 7   ' MSMenu
Const MONGO  = 8   ' BD de MSMenu
Const PAG    = 9   ' MSPagos
Const PGPAG  = 10  ' BD de MSPagos
Const STRIPE = 11  ' Pasarela externa

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU01 - Secuencia Reservar y pagar una racion", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(11)
    nombres(EST)    = "Estudiante"
    nombres(VISTA)  = "Vista (Portal)"
    nombres(GW)     = "Gateway REST (api-gw)"
    nombres(SAGA)   = "SagaOrchestrator (MSIA)"
    nombres(DYNAMO) = "BD Sagas (DynamoDB)"
    nombres(RES)    = "ReservasController (MSReservas)"
    nombres(PGRES)  = "BD Reservas (PostgreSQL)"
    nombres(MENU)   = "PorcionesController (MSMenu)"
    nombres(MONGO)  = "BD Menu (MongoDB)"
    nombres(PAG)    = "PagosController (MSPagos)"
    nombres(PGPAG)  = "BD Pagos (PostgreSQL)"
    nombres(STRIPE) = "Pasarela (Stripe)"

    Dim els(11)
    Dim i
    For i = 0 To 11
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
    For i = 0 To 11
        Dim dobj
        Set dobj = oDiagram.DiagramObjects.AddNew("l=" & (40 + i * 215) & ";r=" & (210 + i * 215) & ";t=-20;b=-90", "")
        dobj.ElementID = els(i).ElementID
        dobj.Sequence = i + 1
        dobj.Update
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==================================================================
    ' ENDPOINT 1: POST /sagas/reservar
    ' ==================================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(EST),    els(VISTA),  1,  "reservar(plato, fecha, turno)"
    AddMsg els(VISTA),  els(GW),     2,  "POST /sagas/reservar"
    AddMsg els(GW),     els(GW),     3,  "requireAuth(token)"
    AddMsg els(GW),     els(SAGA),   4,  "reservar(dto)"
    AddMsg els(SAGA),   els(DYNAMO), 5,  "check_and_lock_idempotency(key)"
    AddMsg els(DYNAMO), els(SAGA),   6,  "return(clave nueva)"
    AddMsg els(SAGA),   els(RES),    7,  "consultarBeca(estudianteId)"
    AddMsg els(RES),    els(PGRES),  8,  "findActivaByEstudiante(id)"
    AddMsg els(PGRES),  els(RES),    9,  "return(beca)"
    AddMsg els(RES),    els(SAGA),   10, "return({ tieneBeca, cubreHoy })"
    AddMsg els(SAGA),   els(DYNAMO), 11, "put_saga(sagaId, RUNNING)"
    AddMsg els(SAGA),   els(RES),    12, "crearReserva(dto)"
    AddMsg els(RES),    els(RES),    13, "ReservarRacionUseCase.execute(dto)"
    AddMsg els(RES),    els(PGRES),  14, "save(reserva 'pendiente')"
    AddMsg els(PGRES),  els(RES),    15, "return(reserva)"
    AddMsg els(RES),    els(SAGA),   16, "return({ reservaId, estado: 'pendiente' })"
    AddMsg els(SAGA),   els(MENU),   17, "apartarPorcion(menuId, platoId)"
    AddMsg els(MENU),   els(MENU),   18, "ApartarPorcionUseCase.ejecutar(dto)"
    AddMsg els(MENU),   els(MONGO),  19, "save(menu, apartadas + 1)"
    AddMsg els(MONGO),  els(MENU),   20, "return(menu)"
    AddMsg els(MENU),   els(SAGA),   21, "return({ ok: true })"
    AddMsg els(SAGA),   els(DYNAMO), 22, "put_saga(sagaId, RESERVED)"
    AddMsg els(SAGA),   els(GW),     23, "return({ reservaId, status: RESERVED })"
    AddMsg els(GW),     els(VISTA),  24, "return(200 OK)"
    AddMsg els(VISTA),  els(EST),    25, "muestra la reserva pendiente de pago"

    ' ==================================================================
    ' ENDPOINT 2: POST /sagas/pagar
    ' ==================================================================
    AddMsg els(EST),    els(VISTA),  26, "pagar(reserva)"
    AddMsg els(VISTA),  els(GW),     27, "POST /sagas/pagar"
    AddMsg els(GW),     els(GW),     28, "requireAuth(token)"
    AddMsg els(GW),     els(SAGA),   29, "pagar(dto)"
    AddMsg els(SAGA),   els(DYNAMO), 30, "check_and_lock_idempotency(key)"
    AddMsg els(DYNAMO), els(SAGA),   31, "return(clave nueva)"
    AddMsg els(SAGA),   els(RES),    32, "obtenerReserva(reservaId)"
    AddMsg els(RES),    els(PGRES),  33, "findById(reservaId)"
    AddMsg els(PGRES),  els(RES),    34, "return(reserva)"
    AddMsg els(RES),    els(SAGA),   35, "return({ estado: 'pendiente' })"
    AddMsg els(SAGA),   els(PAG),    36, "cobrar(dto)"
    AddMsg els(PAG),    els(PAG),    37, "CobrarRacionService.execute(dto)"
    AddMsg els(PAG),    els(STRIPE), 38, "cobrarQr(monto, pagoId)"
    AddMsg els(STRIPE), els(PAG),    39, "return({ paymentUrl, referencia })"
    AddMsg els(PAG),    els(PGPAG),  40, "save(pago) / save(ticket)"
    AddMsg els(PGPAG),  els(PAG),    41, "return(ok)"
    AddMsg els(PAG),    els(SAGA),   42, "return({ pagoId, ticketId, qrPago })"
    AddMsg els(SAGA),   els(DYNAMO), 43, "put_saga(sagaId, PENDING_PAYMENT)"
    AddMsg els(SAGA),   els(GW),     44, "return({ pagoId, status: PENDING_PAYMENT, qrPago })"
    AddMsg els(GW),     els(VISTA),  45, "return(200 OK)"
    AddMsg els(VISTA),  els(EST),    46, "muestra el QR bancario"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU01 creado (camino exitoso, 46 mensajes)." & vbCrLf & _
                   "Agrega a mano los fragmentos 'alt' (becario que no paga, reserva no pendiente, cobro fallido).", 0

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
