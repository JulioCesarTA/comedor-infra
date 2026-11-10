'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE COMUNICACION (COLABORACION) - CU11 Validar QR de ingreso
'
' Endpoint: POST /graphql (mutation validarQr)
' Los participantes se unen con una ASOCIACION y los mensajes van sobre
' esa asociacion (lo mismo que hacer a mano "Add Message from A to B").
' El mensaje lleva solo el nombre: el numero y la flechita los pone EA.
' Misma secuencia que el diagrama de secuencia CU11, resumida.
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
Dim nMsg
Dim oAsoc            ' ConnectorID de la asociacion de cada par de participantes
Dim oCuenta          ' cuantos mensajes hay ya en cada lado de cada asociacion

' Indices de los participantes
Const CAJA  = 0   ' Personal de Caja             (actor)
Const VISTA = 1   ' Vista (Backoffice)           (boundary)
Const GW    = 2   ' Gateway (api-gw)             (control)
Const GQL   = 3   ' Gateway (graphql-gw)         (control)
Const RES   = 4   ' IngresoResolver (MSReservas) (control)
Const PGRES = 5   ' BD Reservas (PostgreSQL)     (entity)
Const ULTIMO = 5

Dim els(5)           ' elementos creados
Dim cx(5), cy(5)     ' centro de cada participante en el diagrama

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Comunicacion ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU11 - Comunicacion Validar QR de ingreso", "Collaboration")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Participantes: nombre y figura ----------
    Dim nombres(5), figuras(5)
    nombres(CAJA)  = "Personal de Caja":              figuras(CAJA)  = "actor"
    nombres(VISTA) = "Vista (Backoffice)":            figuras(VISTA) = "boundary"
    nombres(GW)    = "Gateway (api-gw)":              figuras(GW)    = "control"
    nombres(GQL)   = "Gateway (graphql-gw)":          figuras(GQL)   = "control"
    nombres(RES)   = "IngresoResolver (MSReservas)":  figuras(RES)   = "control"
    nombres(PGRES) = "BD Reservas (PostgreSQL)":      figuras(PGRES) = "entity"

    ' ---------- Posiciones: l, r, t, b (t y b negativos en EA) ----------
    Dim pos(5)
    pos(CAJA)  = Array(40, 90, -70, -140)
    pos(VISTA) = Array(420, 510, -70, -140)
    pos(GW)    = Array(840, 930, -70, -140)
    pos(GQL)   = Array(840, 930, -400, -470)
    pos(RES)   = Array(1260, 1350, -400, -470)
    pos(PGRES) = Array(1680, 1770, -400, -470)

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
    AddAsoc CAJA,  VISTA
    AddAsoc VISTA, GW
    AddAsoc GW,    GQL
    AddAsoc GQL,   RES
    AddAsoc RES,   PGRES

    ' ==============================================================
    ' 2) Mensajes sobre cada asociacion, en orden (ida y vuelta)
    '    AddMsg origen, destino, texto      (el numero lo pone EA)
    ' ==============================================================
    nMsg = 0
    Set oCuenta = CreateObject("Scripting.Dictionary")
    AddMsg CAJA,  VISTA, "escanearQr()"
    AddMsg VISTA, GW,    "validarQr(qr)"
    AddMsg GW,    GQL,   "validarQr(qr)"
    AddMsg GQL,   RES,   "validarQr(qr)"
    AddMsg RES,   PGRES, "findById(reservaId)"
    AddMsg PGRES, RES,   "return(reserva)"
    AddMsg RES,   PGRES, "save(reserva consumida)"
    AddMsg RES,   GQL,   "return(ok, reservaId)"
    AddMsg GQL,   GW,    "return(validarQr)"
    AddMsg GW,    VISTA, "return(200 OK)"
    AddMsg VISTA, CAJA,  "mostrar(Ingreso autorizado)"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama de comunicacion CU11 creado (5 asociaciones, " & nMsg & " mensajes).", 0

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
' Mensaje de comunicacion de origen a destino, colgado de su asociacion.
'   Solo el nombre: EA lo numera segun el orden (SequenceNo).
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
