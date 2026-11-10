'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU03 Controlar inventario y reponer insumos
'
' Endpoint 1: POST /agentes/inventario-compras (tambien lo dispara n8n cada noche)
' Endpoint 2: POST /agentes/propuestas/{id}/aprobar
' Endpoint 3: POST /graphql (mutation registrarLote)
' Solo el CAMINO EXITOSO (timeline limpio).
'
' Fragmentos que agregas a mano (EA no permite crearlos por script):
'   loop por cada proveedor: mensajes 39-43
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
Const ADM      = 0   ' Administrador
Const VISTA    = 1   ' Vista (Backoffice)
Const GW       = 2   ' Gateway (REST)
Const GQL      = 3   ' Gateway (GraphQL)
Const IA       = 4   ' AgentesRouter (MSIA)
Const SQL      = 5   ' BD Agentes (SQLite)
Const N8N      = 6   ' Automatizacion (n8n)
Const FCM      = 7   ' Notificaciones (Firebase)
Const TG       = 8   ' Notificaciones (Telegram)
Const MCP      = 9   ' McpController (MSMenu)
Const SUBGRAFO = 10  ' MenuGraphqlController (MSMenu)
Const PROV     = 11  ' ProveedoresController (MSPagos)
Const MONGO    = 12  ' BD Menu (MongoDB)
Const PGPAG    = 13  ' BD Pagos (PostgreSQL)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU03 - Secuencia Controlar inventario y reponer insumos", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(13)
    nombres(ADM)      = "Administrador"
    nombres(VISTA)    = "Vista (Backoffice)"
    nombres(GW)       = "Gateway (api-gw)"
    nombres(GQL)      = "Gateway (graphql-gw)"
    nombres(IA)       = "AgentesRouter (MSIA)"
    nombres(SQL)      = "BD Agentes (SQLite)"
    nombres(N8N)      = "Automatizacion (n8n)"
    nombres(FCM)      = "Notificaciones (FCM)"
    nombres(TG)       = "Notificaciones (Telegram)"
    nombres(MCP)      = "McpController (MSMenu)"
    nombres(SUBGRAFO) = "MenuGraphqlController (MSMenu)"
    nombres(PROV)     = "ProveedoresController (MSPagos)"
    nombres(MONGO)    = "BD Menu (MongoDB)"
    nombres(PGPAG)    = "BD Pagos (PostgreSQL)"

    Dim els(13)
    Dim i
    For i = 0 To 13
        Dim el
        If i = ADM Then
            Set el = oPackage.Elements.AddNew(nombres(i), "Actor")
        Else
            Set el = oPackage.Elements.AddNew(nombres(i), "Sequence")
        End If
        el.Update
        Set els(i) = el
    Next
    oPackage.Elements.Refresh

    ' ---------- Colocar los participantes en el diagrama ----------
    For i = 0 To 13
        Dim dobj
        Set dobj = oDiagram.DiagramObjects.AddNew("l=" & (40 + i * 215) & ";r=" & (210 + i * 215) & ";t=-20;b=-90", "")
        dobj.ElementID = els(i).ElementID
        dobj.Sequence = i + 1
        dobj.Update
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==============================================================
    ' Endpoint 1: POST /agentes/inventario-compras (tambien lo dispara n8n cada noche)
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(ADM),      els(VISTA),    1,   "correr('inventario-compras')"
    AddMsg els(VISTA),    els(GW),       2,   "POST /agentes/inventario-compras"
    AddMsg els(GW),       els(GW),       3,   "requireAuth(token)"
    AddMsg els(GW),       els(IA),       4,   "inv(mision)"
    AddMsg els(IA),       els(IA),       5,   "InventarioComprasAgent.run(objetivo)"
    AddMsg els(IA),       els(MCP),      6,   "MCP tools/call crear_orden_compra_borrador"
    AddMsg els(MCP),      els(MONGO),    7,   "findAll()"
    AddMsg els(MONGO),    els(MCP),      8,   "return(insumos)"
    AddMsg els(MCP),      els(IA),       9,   "return(lineas del borrador (stock bajo))"
    AddMsg els(IA),       els(MCP),      10,  "MCP tools/call lotes_por_vencer(dias = 7)"
    AddMsg els(MCP),      els(MONGO),    11,  "findAll()"
    AddMsg els(MONGO),    els(MCP),      12,  "return(insumos)"
    AddMsg els(MCP),      els(IA),       13,  "return(lotes por vencer)"
    AddMsg els(IA),       els(IA),       14,  "agrega precio, proveedor y severidad"
    AddMsg els(IA),       els(IA),       15,  "proponer_inventario(resultado)"
    AddMsg els(IA),       els(SQL),      16,  "crear_si_no_hay_vigente(propuesta)"
    AddMsg els(SQL),      els(IA),       17,  "return(propuesta PENDIENTE)"
    AddMsg els(IA),       els(N8N),      18,  "POST /webhook/notificar(push, 'Inventario: alerta')"
    AddMsg els(N8N),      els(FCM),      19,  "messages:send(token, titulo, cuerpo)"
    AddMsg els(FCM),      els(N8N),      20,  "return(enviado)"
    AddMsg els(N8N),      els(IA),       21,  "return({ ok: true })"
    AddMsg els(IA),       els(SQL),      22,  "encolar(mensajeAdmin, propuestaId)"
    AddMsg els(IA),       els(N8N),      23,  "POST /webhook/notificar(telegram, mensajeAdmin)"
    AddMsg els(N8N),      els(TG),       24,  "sendMessage(chat, mensajeAdmin, botones aprobar / rechazar)"
    AddMsg els(TG),       els(N8N),      25,  "return(enviado)"
    AddMsg els(N8N),      els(IA),       26,  "return({ ok: true })"
    AddMsg els(IA),       els(GW),       27,  "return({ severidad, ordenesBorrador, propuestaCompra })"
    AddMsg els(GW),       els(VISTA),    28,  "return(200 OK)"
    AddMsg els(VISTA),    els(ADM),      29,  "muestra la orden de compra propuesta"
    ' ==============================================================
    ' Endpoint 2: POST /agentes/propuestas/{id}/aprobar
    ' ==============================================================
    AddMsg els(ADM),      els(VISTA),    30,  "resolver(propuesta, aprobar = true)"
    AddMsg els(VISTA),    els(GW),       31,  "POST /agentes/propuestas/{id}/aprobar"
    AddMsg els(GW),       els(GW),       32,  "requireAuth(token)"
    AddMsg els(GW),       els(IA),       33,  "aprobar(id)"
    AddMsg els(IA),       els(IA),       34,  "propuestas.resolver(id, aprobar)"
    AddMsg els(IA),       els(SQL),      35,  "tomar_pendiente(id, EJECUTANDO)"
    AddMsg els(SQL),      els(IA),       36,  "return(ok)"
    AddMsg els(IA),       els(IA),       37,  "_ejecutar_compra(payload, id)"
    AddMsg els(IA),       els(N8N),      38,  "POST /webhook/orden-aprobada(ordenId, proveedores)"
    ' loop por cada proveedor (mensajes 39 a 43)
    AddMsg els(N8N),      els(PROV),     39,  "POST /proveedores/pagos(ordenId, proveedor, monto, detalle)"
    AddMsg els(PROV),     els(PROV),     40,  "ObligacionesProveedorService.registrar(...)"
    AddMsg els(PROV),     els(PGPAG),    41,  "guardarSiNoExiste(obligacion)"
    AddMsg els(PGPAG),    els(PROV),     42,  "return(obligacion PENDIENTE)"
    AddMsg els(PROV),     els(N8N),      43,  "return(201 Created)"
    AddMsg els(N8N),      els(IA),       44,  "return({ ok: true, registradas })"
    AddMsg els(IA),       els(SQL),      45,  "cerrar(id, EJECUTADA)"
    AddMsg els(IA),       els(SQL),      46,  "encolar(orden aprobada y resultado)"
    AddMsg els(IA),       els(N8N),      47,  "POST /webhook/notificar(telegram, orden aprobada)"
    AddMsg els(N8N),      els(TG),       48,  "sendMessage(chat, orden aprobada y resultado)"
    AddMsg els(TG),       els(N8N),      49,  "return(enviado)"
    AddMsg els(N8N),      els(IA),       50,  "return({ ok: true })"
    AddMsg els(IA),       els(GW),       51,  "return({ estado: EJECUTADA, resultado })"
    AddMsg els(GW),       els(VISTA),    52,  "return(200 OK)"
    AddMsg els(VISTA),    els(ADM),      53,  "muestra la orden aprobada"
    ' ==============================================================
    ' Endpoint 3: POST /graphql (mutation registrarLote)
    ' ==============================================================
    AddMsg els(ADM),      els(VISTA),    54,  "recibirLote(insumo, cantidad, vence)"
    AddMsg els(VISTA),    els(GW),       55,  "POST /graphql"
    AddMsg els(GW),       els(GW),       56,  "requireAuth(token)"
    AddMsg els(GW),       els(GQL),      57,  "mutation registrarLote(insumoId, loteId, cantidad, unidad, vence)"
    AddMsg els(GQL),      els(SUBGRAFO), 58,  "registrarLote(insumoId, loteId, cantidad, unidad, vence)"
    AddMsg els(SUBGRAFO), els(SUBGRAFO), 59,  "RegistrarLoteUseCase.ejecutar(entrada)"
    AddMsg els(SUBGRAFO), els(MONGO),    60,  "findById(insumoId)"
    AddMsg els(MONGO),    els(SUBGRAFO), 61,  "return(insumo)"
    AddMsg els(SUBGRAFO), els(SUBGRAFO), 62,  "insumo.registrarLote(lote)"
    AddMsg els(SUBGRAFO), els(MONGO),    63,  "save(insumo)"
    AddMsg els(MONGO),    els(SUBGRAFO), 64,  "return(insumo)"
    AddMsg els(SUBGRAFO), els(GQL),      65,  "return({ ok: true, insumoId, loteId })"
    AddMsg els(GQL),      els(GW),       66,  "return({ data: { registrarLote } })"
    AddMsg els(GW),       els(VISTA),    67,  "return(200 OK)"
    AddMsg els(VISTA),    els(ADM),      68,  "muestra 'Lote registrado'"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU03 creado (camino exitoso, 68 mensajes)." & vbCrLf & _
                   "Agrega a mano: loop por cada proveedor: mensajes 39-43.", 0

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
