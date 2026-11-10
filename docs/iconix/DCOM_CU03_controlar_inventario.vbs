'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE COMUNICACION (COLABORACION) - CU03 Controlar inventario y reponer insumos
'
' Endpoint 1: POST /agentes/inventario-compras        (grupo 0: 0.1, 0.2 ...)
' Endpoint 2: POST /agentes/propuestas/{id}/aprobar   (grupo 1: 1.1, 1.2 ...)
' Endpoint 3: POST /graphql (mutation registrarLote)  (grupo 2: 2.1, 2.2 ...)
' Los participantes se unen con una ASOCIACION y los mensajes van sobre
' esa asociacion (lo mismo que hacer a mano "Add Message from A to B").
' El mensaje lleva solo el nombre: el numero y la flechita los pone EA.
' Misma secuencia que el diagrama de secuencia CU03 (camino exitoso),
' sin las llamadas a si mismo. El loop "por cada proveedor" queda como
' un solo registro (en comunicacion no hay fragmentos).
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
Const ADM      = 0   ' Administrador                   (actor)
Const VISTA    = 1   ' Vista (Backoffice)              (boundary)
Const GW       = 2   ' Gateway (api-gw)                (control)
Const GQL      = 3   ' Gateway (graphql-gw)            (control)
Const IA       = 4   ' AgentesRouter (MSIA)            (control)
Const SQL      = 5   ' BD Agentes (SQLite)             (entity)
Const N8N      = 6   ' Automatizacion (n8n)            (control)
Const FCM      = 7   ' Notificaciones (FCM)            (boundary)
Const TG       = 8   ' Notificaciones (Telegram)       (boundary)
Const MCP      = 9   ' McpController (MSMenu)          (control)
Const SUBGRAFO = 10  ' MenuGraphqlController (MSMenu)  (control)
Const PROV     = 11  ' ProveedoresController (MSPagos) (control)
Const MONGO    = 12  ' BD Menu (MongoDB)               (entity)
Const PGPAG    = 13  ' BD Pagos (PostgreSQL)           (entity)
Const ULTIMO   = 13

Dim els(13)          ' elementos creados
Dim cx(13), cy(13)   ' centro de cada participante en el diagrama

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Comunicacion ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU03 - Comunicacion Controlar inventario y reponer insumos", "Collaboration")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Participantes: nombre y figura ----------
    Dim nombres(13), figuras(13)
    nombres(ADM)      = "Administrador":                     figuras(ADM)      = "actor"
    nombres(VISTA)    = "Vista (Backoffice)":                figuras(VISTA)    = "boundary"
    nombres(GW)       = "Gateway (api-gw)":                  figuras(GW)       = "control"
    nombres(GQL)      = "Gateway (graphql-gw)":              figuras(GQL)      = "control"
    nombres(IA)       = "AgentesRouter (MSIA)":              figuras(IA)       = "control"
    nombres(SQL)      = "BD Agentes (SQLite)":               figuras(SQL)      = "entity"
    nombres(N8N)      = "Automatizacion (n8n)":              figuras(N8N)      = "control"
    nombres(FCM)      = "Notificaciones (FCM)":              figuras(FCM)      = "boundary"
    nombres(TG)       = "Notificaciones (Telegram)":         figuras(TG)       = "boundary"
    nombres(MCP)      = "McpController (MSMenu)":            figuras(MCP)      = "control"
    nombres(SUBGRAFO) = "MenuGraphqlController (MSMenu)":    figuras(SUBGRAFO) = "control"
    nombres(PROV)     = "ProveedoresController (MSPagos)":   figuras(PROV)     = "control"
    nombres(MONGO)    = "BD Menu (MongoDB)":                 figuras(MONGO)    = "entity"
    nombres(PGPAG)    = "BD Pagos (PostgreSQL)":             figuras(PGPAG)    = "entity"

    ' ---------- Posiciones: l, r, t, b (t y b negativos en EA) ----------
    ' Fila 1: el pedido entra por la izquierda y llega al agente; su BD a la derecha
    ' Fila 2: graphql-gw bajo el api-gw, MCP bajo el agente, n8n y FCM a la derecha
    ' Fila 3: subgrafo GraphQL y Mongo (compartido con MCP), Telegram, proveedores y su BD
    Dim pos(13)
    pos(ADM)      = Array(40, 90, -200, -270)
    pos(VISTA)    = Array(400, 490, -200, -270)
    pos(GW)       = Array(760, 850, -200, -270)
    pos(IA)       = Array(1120, 1210, -200, -270)
    pos(SQL)      = Array(1600, 1690, -200, -270)
    pos(GQL)      = Array(760, 850, -540, -610)
    pos(MCP)      = Array(1120, 1210, -540, -610)
    pos(N8N)      = Array(1600, 1690, -540, -610)
    pos(FCM)      = Array(2000, 2090, -540, -610)
    pos(SUBGRAFO) = Array(760, 850, -880, -950)
    pos(MONGO)    = Array(1120, 1210, -880, -950)
    pos(TG)       = Array(1600, 1690, -880, -950)
    pos(PROV)     = Array(2000, 2090, -880, -950)
    pos(PGPAG)    = Array(2400, 2490, -880, -950)

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
    AddAsoc ADM,      VISTA
    AddAsoc VISTA,    GW
    AddAsoc GW,       IA
    AddAsoc GW,       GQL
    AddAsoc GQL,      SUBGRAFO
    AddAsoc SUBGRAFO, MONGO
    AddAsoc IA,       SQL
    AddAsoc IA,       MCP
    AddAsoc MCP,      MONGO
    AddAsoc IA,       N8N
    AddAsoc N8N,      FCM
    AddAsoc N8N,      TG
    AddAsoc N8N,      PROV
    AddAsoc PROV,     PGPAG

    ' ==============================================================
    ' 2) Mensajes sobre cada asociacion, en orden (ida y vuelta)
    '    AddMsg origen, destino, texto      (el numero lo pone el script)
    ' ==============================================================
    nMsg = 0
    nGrupo = -1
    Set oCuenta = CreateObject("Scripting.Dictionary")

    ' ---- Endpoint 1: POST /agentes/inventario-compras  (grupo 0) ----
    NuevoGrupo
    AddMsg ADM,   VISTA, "correr(inventario-compras)"
    AddMsg VISTA, GW,    "inventarioCompras(mision)"
    AddMsg GW,    IA,    "inv(mision)"
    AddMsg IA,    MCP,   "crear_orden_compra_borrador()"
    AddMsg MCP,   MONGO, "findAll()"
    AddMsg MONGO, MCP,   "return(insumos)"
    AddMsg MCP,   IA,    "return(lineas del borrador)"
    AddMsg IA,    MCP,   "lotes_por_vencer(dias = 7)"
    AddMsg MCP,   MONGO, "findAll()"
    AddMsg MONGO, MCP,   "return(insumos)"
    AddMsg MCP,   IA,    "return(lotes por vencer)"
    AddMsg IA,    SQL,   "crear_si_no_hay_vigente(propuesta)"
    AddMsg SQL,   IA,    "return(propuesta PENDIENTE)"
    AddMsg IA,    N8N,   "notificar(push, Inventario alerta)"
    AddMsg N8N,   FCM,   "send(token, titulo, cuerpo)"
    AddMsg FCM,   N8N,   "return(enviado)"
    AddMsg N8N,   IA,    "return(ok)"
    AddMsg IA,    SQL,   "encolar(mensajeAdmin, propuestaId)"
    AddMsg IA,    N8N,   "notificar(telegram, mensajeAdmin)"
    AddMsg N8N,   TG,    "sendMessage(chat, mensajeAdmin, botones)"
    AddMsg TG,    N8N,   "return(enviado)"
    AddMsg N8N,   IA,    "return(ok)"
    AddMsg IA,    GW,    "return(severidad, ordenesBorrador, propuestaCompra)"
    AddMsg GW,    VISTA, "return(200 OK)"
    AddMsg VISTA, ADM,   "mostrar(orden de compra propuesta)"

    ' ---- Endpoint 2: POST /agentes/propuestas/{id}/aprobar  (grupo 1) ----
    NuevoGrupo
    AddMsg ADM,   VISTA, "resolver(propuesta, aprobar)"
    AddMsg VISTA, GW,    "aprobar(id)"
    AddMsg GW,    IA,    "aprobar(id)"
    AddMsg IA,    SQL,   "tomar_pendiente(id, EJECUTANDO)"
    AddMsg SQL,   IA,    "return(ok)"
    AddMsg IA,    N8N,   "ordenAprobada(ordenId, proveedores)"
    AddMsg N8N,   PROV,  "registrar(ordenId, proveedor, monto, detalle)"
    AddMsg PROV,  PGPAG, "guardarSiNoExiste(obligacion)"
    AddMsg PGPAG, PROV,  "return(obligacion PENDIENTE)"
    AddMsg PROV,  N8N,   "return(201 Created)"
    AddMsg N8N,   IA,    "return(ok, registradas)"
    AddMsg IA,    SQL,   "cerrar(id, EJECUTADA)"
    AddMsg IA,    SQL,   "encolar(orden aprobada y resultado)"
    AddMsg IA,    N8N,   "notificar(telegram, orden aprobada)"
    AddMsg N8N,   TG,    "sendMessage(chat, orden aprobada y resultado)"
    AddMsg TG,    N8N,   "return(enviado)"
    AddMsg N8N,   IA,    "return(ok)"
    AddMsg IA,    GW,    "return(EJECUTADA, resultado)"
    AddMsg GW,    VISTA, "return(200 OK)"
    AddMsg VISTA, ADM,   "mostrar(orden aprobada)"

    ' ---- Endpoint 3: POST /graphql (mutation registrarLote)  (grupo 2) ----
    NuevoGrupo
    AddMsg ADM,      VISTA,    "recibirLote(insumo, cantidad, vence)"
    AddMsg VISTA,    GW,       "registrarLote(insumoId, loteId, cantidad, unidad, vence)"
    AddMsg GW,       GQL,      "registrarLote(insumoId, loteId, cantidad, unidad, vence)"
    AddMsg GQL,      SUBGRAFO, "registrarLote(insumoId, loteId, cantidad, unidad, vence)"
    AddMsg SUBGRAFO, MONGO,    "findById(insumoId)"
    AddMsg MONGO,    SUBGRAFO, "return(insumo)"
    AddMsg SUBGRAFO, MONGO,    "save(insumo)"
    AddMsg MONGO,    SUBGRAFO, "return(insumo)"
    AddMsg SUBGRAFO, GQL,      "return(ok, insumoId, loteId)"
    AddMsg GQL,      GW,       "return(registrarLote)"
    AddMsg GW,       VISTA,    "return(200 OK)"
    AddMsg VISTA,    ADM,      "mostrar(Lote registrado)"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama de comunicacion CU03 creado (14 asociaciones, " & nMsg & " mensajes).", 0

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
