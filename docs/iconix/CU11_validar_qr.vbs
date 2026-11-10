'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU11 Validar QR de ingreso
'
' Endpoint: POST /graphql (mutation validarQr)
' Solo el CAMINO EXITOSO (timeline limpio).
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
Const CAJA  = 0   ' Personal de Caja
Const VISTA = 1   ' Vista (Backoffice)
Const GW    = 2   ' Gateway (REST)
Const GQL   = 3   ' Gateway (GraphQL)
Const RES   = 4   ' IngresoResolver (MSReservas)
Const PGRES = 5   ' BD Reservas (PostgreSQL)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU11 - Secuencia Validar QR de ingreso", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(5)
    nombres(CAJA)  = "Personal de Caja"
    nombres(VISTA) = "Vista (Backoffice)"
    nombres(GW)    = "Gateway (api-gw)"
    nombres(GQL)   = "Gateway (graphql-gw)"
    nombres(RES)   = "IngresoResolver (MSReservas)"
    nombres(PGRES) = "BD Reservas (PostgreSQL)"

    Dim els(5)
    Dim i
    For i = 0 To 5
        Dim el
        If i = CAJA Then
            Set el = oPackage.Elements.AddNew(nombres(i), "Actor")
        Else
            Set el = oPackage.Elements.AddNew(nombres(i), "Sequence")
        End If
        el.Update
        Set els(i) = el
    Next
    oPackage.Elements.Refresh

    ' ---------- Colocar los participantes en el diagrama ----------
    For i = 0 To 5
        Dim dobj
        Set dobj = oDiagram.DiagramObjects.AddNew("l=" & (40 + i * 215) & ";r=" & (210 + i * 215) & ";t=-20;b=-90", "")
        dobj.ElementID = els(i).ElementID
        dobj.Sequence = i + 1
        dobj.Update
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==============================================================
    ' Endpoint: POST /graphql (mutation validarQr)
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(CAJA),  els(VISTA), 1,   "startCamera()"
    AddMsg els(VISTA), els(VISTA), 2,   "html5QrCode.start() lee el QR"
    AddMsg els(VISTA), els(VISTA), 3,   "validar()"
    AddMsg els(VISTA), els(GW),    4,   "POST /graphql"
    AddMsg els(GW),    els(GW),    5,   "requireAuth(token)"
    AddMsg els(GW),    els(GQL),   6,   "mutation validarQr(qr)"
    AddMsg els(GQL),   els(RES),   7,   "validarQr(qr)"
    AddMsg els(RES),   els(RES),   8,   "ValidarIngresoUseCase.execute(qr)"
    AddMsg els(RES),   els(PGRES), 9,   "findById(reservaId)"
    AddMsg els(PGRES), els(RES),   10,  "return(reserva)"
    AddMsg els(RES),   els(RES),   11,  "reserva.marcarConsumida()"
    AddMsg els(RES),   els(PGRES), 12,  "save(reserva 'consumida')"
    AddMsg els(PGRES), els(RES),   13,  "return(reserva)"
    AddMsg els(RES),   els(GQL),   14,  "return({ ok: true, reservaId })"
    AddMsg els(GQL),   els(GW),    15,  "return({ data: { validarQr } })"
    AddMsg els(GW),    els(VISTA), 16,  "return(200 OK)"
    AddMsg els(VISTA), els(CAJA),  17,  "muestra 'Ingreso autorizado'"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU11 creado (camino exitoso, 17 mensajes).", 0

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
