'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE COMUNICACION (COLABORACION) - CU01 Reservar y pagar una racion
'
' Endpoint 1: POST /sagas/reservar   Endpoint 2: POST /sagas/pagar
' Los participantes se unen con una ASOCIACION y los mensajes van sobre
' esa asociacion (lo mismo que hacer a mano "Add Message from A to B").
' El mensaje lleva solo el nombre: el numero y la flechita los pone EA.
' Misma secuencia que el diagrama de secuencia CU01 (camino exitoso),
' sin las llamadas a si mismo.
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
Const VISTA  = 1   ' Vista (Portal)                  (boundary)
Const GW     = 2   ' Gateway (api-gw)                (control)
Const SAGA   = 3   ' SagaOrchestrator (MSIA)         (control)
Const DYNAMO = 4   ' BD Sagas (DynamoDB)             (entity)
Const RES    = 5   ' ReservasController (MSReservas) (control)
Const PGRES  = 6   ' BD Reservas (PostgreSQL)        (entity)
Const MENU   = 7   ' PorcionesController (MSMenu)    (control)
Const MONGO  = 8   ' BD Menu (MongoDB)               (entity)
Const PAG    = 9   ' PagosController (MSPagos)       (control)
Const PGPAG  = 10  ' BD Pagos (PostgreSQL)           (entity)
Const STRIPE = 11  ' Pasarela (Stripe)               (boundary)
Const ULTIMO = 11

Dim els(11)          ' elementos creados
Dim cx(11), cy(11)   ' centro de cada participante en el diagrama

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Comunicacion ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU01 - Comunicacion Reservar y pagar una racion", "Collaboration")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Participantes: nombre y figura ----------
    Dim nombres(11), figuras(11)
    nombres(EST)    = "Estudiante":                        figuras(EST)    = "actor"
    nombres(VISTA)  = "Vista (Portal)":                    figuras(VISTA)  = "boundary"
    nombres(GW)     = "Gateway (api-gw)":                  figuras(GW)     = "control"
    nombres(SAGA)   = "SagaOrchestrator (MSIA)":           figuras(SAGA)   = "control"
    nombres(DYNAMO) = "BD Sagas (DynamoDB)":               figuras(DYNAMO) = "entity"
    nombres(RES)    = "ReservasController (MSReservas)":   figuras(RES)    = "control"
    nombres(PGRES)  = "BD Reservas (PostgreSQL)":          figuras(PGRES)  = "entity"
    nombres(MENU)   = "PorcionesController (MSMenu)":      figuras(MENU)   = "control"
    nombres(MONGO)  = "BD Menu (MongoDB)":                 figuras(MONGO)  = "entity"
    nombres(PAG)    = "PagosController (MSPagos)":         figuras(PAG)    = "control"
    nombres(PGPAG)  = "BD Pagos (PostgreSQL)":             figuras(PGPAG)  = "entity"
    nombres(STRIPE) = "Pasarela (Stripe)":                 figuras(STRIPE) = "boundary"

    ' ---------- Posiciones: l, r, t, b (t y b negativos en EA) ----------
    ' Fila de arriba: el pedido entra por la izquierda y llega al orquestador
    ' Fila del medio: los tres microservicios que llama la saga
    ' Fila de abajo:  sus bases y la pasarela
    Dim pos(11)
    pos(EST)    = Array(40, 90, -80, -150)
    pos(VISTA)  = Array(400, 490, -80, -150)
    pos(GW)     = Array(760, 850, -80, -150)
    pos(SAGA)   = Array(1120, 1210, -80, -150)
    pos(DYNAMO) = Array(1560, 1650, -80, -150)
    pos(RES)    = Array(700, 790, -420, -490)
    pos(PGRES)  = Array(300, 390, -420, -490)
    pos(MENU)   = Array(1120, 1210, -420, -490)
    pos(MONGO)  = Array(1120, 1210, -720, -790)
    pos(PAG)    = Array(1560, 1650, -420, -490)
    pos(PGPAG)  = Array(2000, 2090, -420, -490)
    pos(STRIPE) = Array(1560, 1650, -720, -790)

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
    AddAsoc EST,   VISTA
    AddAsoc VISTA, GW
    AddAsoc GW,    SAGA
    AddAsoc SAGA,  DYNAMO
    AddAsoc SAGA,  RES
    AddAsoc RES,   PGRES
    AddAsoc SAGA,  MENU
    AddAsoc MENU,  MONGO
    AddAsoc SAGA,  PAG
    AddAsoc PAG,   PGPAG
    AddAsoc PAG,   STRIPE

    ' ==============================================================
    ' 2) Mensajes sobre cada asociacion, en orden (ida y vuelta)
    '    AddMsg origen, destino, texto      (el numero lo pone EA)
    ' ==============================================================
    nMsg = 0
    nGrupo = -1
    Set oCuenta = CreateObject("Scripting.Dictionary")

    ' ---- Endpoint 1: POST /sagas/reservar  (grupo 0: 0.1, 0.2, ...) ----
    NuevoGrupo
    AddMsg EST,    VISTA,  "reservar(plato, fecha, turno)"
    AddMsg VISTA,  GW,     "reservar(plato, fecha, turno)"
    AddMsg GW,     SAGA,   "reservar(dto)"
    AddMsg SAGA,   DYNAMO, "bloquear_idempotencia(key)"
    AddMsg DYNAMO, SAGA,   "return(clave nueva)"
    AddMsg SAGA,   RES,    "consultarBeca(estudianteId)"
    AddMsg RES,    PGRES,  "findActivaByEstudiante(id)"
    AddMsg PGRES,  RES,    "return(beca)"
    AddMsg RES,    SAGA,   "return(tieneBeca, cubreHoy)"
    AddMsg SAGA,   DYNAMO, "guardar_saga(sagaId, RUNNING)"
    AddMsg SAGA,   RES,    "crearReserva(dto)"
    AddMsg RES,    PGRES,  "save(reserva pendiente)"
    AddMsg PGRES,  RES,    "return(reserva)"
    AddMsg RES,    SAGA,   "return(reservaId, pendiente)"
    AddMsg SAGA,   MENU,   "apartarPorcion(menuId, platoId)"
    AddMsg MENU,   MONGO,  "save(menu, apartadas + 1)"
    AddMsg MONGO,  MENU,   "return(menu)"
    AddMsg MENU,   SAGA,   "return(ok)"
    AddMsg SAGA,   DYNAMO, "guardar_saga(sagaId, RESERVED)"
    AddMsg SAGA,   GW,     "return(reservaId, RESERVED)"
    AddMsg GW,     VISTA,  "return(200 OK)"
    AddMsg VISTA,  EST,    "mostrar(reserva pendiente de pago)"

    ' ---- Endpoint 2: POST /sagas/pagar  (grupo 1: 1.1, 1.2, ...) ----
    NuevoGrupo
    AddMsg EST,    VISTA,  "pagar(reserva)"
    AddMsg VISTA,  GW,     "pagar(reservaId)"
    AddMsg GW,     SAGA,   "pagar(dto)"
    AddMsg SAGA,   DYNAMO, "bloquear_idempotencia(key)"
    AddMsg DYNAMO, SAGA,   "return(clave nueva)"
    AddMsg SAGA,   RES,    "obtenerReserva(reservaId)"
    AddMsg RES,    PGRES,  "findById(reservaId)"
    AddMsg PGRES,  RES,    "return(reserva)"
    AddMsg RES,    SAGA,   "return(estado pendiente)"
    AddMsg SAGA,   PAG,    "cobrar(dto)"
    AddMsg PAG,    STRIPE, "cobrarQr(monto, pagoId)"
    AddMsg STRIPE, PAG,    "return(paymentUrl, referencia)"
    AddMsg PAG,    PGPAG,  "save(pago, ticket)"
    AddMsg PGPAG,  PAG,    "return(ok)"
    AddMsg PAG,    SAGA,   "return(pagoId, ticketId, qrPago)"
    AddMsg SAGA,   DYNAMO, "guardar_saga(sagaId, PENDING_PAYMENT)"
    AddMsg SAGA,   GW,     "return(pagoId, PENDING_PAYMENT, qrPago)"
    AddMsg GW,     VISTA,  "return(200 OK)"
    AddMsg VISTA,  EST,    "mostrar(QR bancario)"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama de comunicacion CU01 creado (11 asociaciones, " & nMsg & " mensajes).", 0

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
