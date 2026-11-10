'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU05 Dar una mision a un agente de IA y aprobar sus propuestas
'
' Endpoint 1: POST /agentes/{agente}
' Endpoint 2: GET /agentes/propuestas y GET /agentes/telegram
' Endpoint 3: POST /agentes/propuestas/{id}/aprobar
' Solo el CAMINO EXITOSO (timeline limpio).
'
' Fragmentos que agregas a mano (EA no permite crearlos por script):
'   alt propuesta de menu: mensajes 52-61
'   else propuesta de compra: mensajes 62-69
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
Const ADM   = 0   ' Administrador
Const VISTA = 1   ' Vista (Backoffice)
Const GW    = 2   ' Gateway (REST)
Const IA    = 3   ' AgentesRouter (MSIA)
Const SQL   = 4   ' BD Agentes (SQLite)
Const N8N   = 5   ' Automatizacion (n8n)
Const FCM   = 6   ' Notificaciones (Firebase)
Const TG    = 7   ' Notificaciones (Telegram)
Const MCP   = 8   ' McpController (MSMenu)
Const PROV  = 9   ' ProveedoresController (MSPagos)
Const MONGO = 10  ' BD Menu (MongoDB)
Const PGPAG = 11  ' BD Pagos (PostgreSQL)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU05 - Secuencia Dar una mision a un agente de IA y aprobar sus propuestas", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(11)
    nombres(ADM)   = "Administrador"
    nombres(VISTA) = "Vista (Backoffice)"
    nombres(GW)    = "Gateway (api-gw)"
    nombres(IA)    = "AgentesRouter (MSIA)"
    nombres(SQL)   = "BD Agentes (SQLite)"
    nombres(N8N)   = "Automatizacion (n8n)"
    nombres(FCM)   = "Notificaciones (FCM)"
    nombres(TG)    = "Notificaciones (Telegram)"
    nombres(MCP)   = "McpController (MSMenu)"
    nombres(PROV)  = "ProveedoresController (MSPagos)"
    nombres(MONGO) = "BD Menu (MongoDB)"
    nombres(PGPAG) = "BD Pagos (PostgreSQL)"

    Dim els(11)
    Dim i
    For i = 0 To 11
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
    For i = 0 To 11
        Dim dobj
        Set dobj = oDiagram.DiagramObjects.AddNew("l=" & (40 + i * 215) & ";r=" & (210 + i * 215) & ";t=-20;b=-90", "")
        dobj.ElementID = els(i).ElementID
        dobj.Sequence = i + 1
        dobj.Update
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==============================================================
    ' Endpoint 1: POST /agentes/{agente}
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(ADM),   els(VISTA), 1,   "correr(agente)"
    AddMsg els(VISTA), els(GW),    2,   "POST /agentes/{agente}"
    AddMsg els(GW),    els(GW),    3,   "requireAuth(token)"
    AddMsg els(GW),    els(IA),    4,   "planif(mision) o inv(mision)"
    AddMsg els(IA),    els(IA),    5,   "agente.run(objetivo)"
    AddMsg els(IA),    els(MCP),   6,   "MCP tools/call ver_stock_bajo o crear_orden_compra_borrador"
    AddMsg els(MCP),   els(MONGO), 7,   "findAll()"
    AddMsg els(MONGO), els(MCP),   8,   "return(insumos)"
    AddMsg els(MCP),   els(IA),    9,   "return(insumos o lineas del borrador)"
    AddMsg els(IA),    els(MCP),   10,  "MCP tools/call lotes_por_vencer(dias)"
    AddMsg els(MCP),   els(MONGO), 11,  "findAll()"
    AddMsg els(MONGO), els(MCP),   12,  "return(insumos)"
    AddMsg els(MCP),   els(IA),    13,  "return(lotes por vencer)"
    AddMsg els(IA),    els(IA),    14,  "proponer_menu(r) o proponer_inventario(r)"
    AddMsg els(IA),    els(SQL),   15,  "crear_si_no_hay_vigente(propuesta)"
    AddMsg els(SQL),   els(IA),    16,  "return(propuesta PENDIENTE)"
    AddMsg els(IA),    els(N8N),   17,  "POST /webhook/notificar(push, titulo, cuerpo)"
    AddMsg els(N8N),   els(FCM),   18,  "messages:send(token, titulo, cuerpo)"
    AddMsg els(FCM),   els(N8N),   19,  "return(enviado)"
    AddMsg els(N8N),   els(IA),    20,  "return({ ok: true })"
    AddMsg els(IA),    els(SQL),   21,  "encolar(resumen, propuestaId)"
    AddMsg els(IA),    els(N8N),   22,  "POST /webhook/notificar(telegram, resumen)"
    AddMsg els(N8N),   els(TG),    23,  "sendMessage(chat, resumen, botones aprobar / rechazar)"
    AddMsg els(TG),    els(N8N),   24,  "return(enviado)"
    AddMsg els(N8N),   els(IA),    25,  "return({ ok: true })"
    AddMsg els(IA),    els(GW),    26,  "return({ resultado, propuesta })"
    AddMsg els(GW),    els(VISTA), 27,  "return(200 OK)"
    AddMsg els(VISTA), els(ADM),   28,  "avisa 'Propuesta creada'"
    ' ==============================================================
    ' Endpoint 2: GET /agentes/propuestas y GET /agentes/telegram
    ' ==============================================================
    AddMsg els(ADM),   els(VISTA), 29,  "abrir panel de agentes"
    AddMsg els(VISTA), els(VISTA), 30,  "refrescar()"
    AddMsg els(VISTA), els(GW),    31,  "GET /agentes/propuestas"
    AddMsg els(GW),    els(GW),    32,  "requireAuth(token)"
    AddMsg els(GW),    els(IA),    33,  "listar_propuestas()"
    AddMsg els(IA),    els(SQL),   34,  "listar(estado, limite)"
    AddMsg els(SQL),   els(IA),    35,  "return(propuestas)"
    AddMsg els(IA),    els(GW),    36,  "return(propuestas)"
    AddMsg els(GW),    els(VISTA), 37,  "return(200 OK)"
    AddMsg els(VISTA), els(GW),    38,  "GET /agentes/telegram"
    AddMsg els(GW),    els(IA),    39,  "telegram()"
    AddMsg els(IA),    els(IA),    40,  "telegram_bot.estado()"
    AddMsg els(IA),    els(GW),    41,  "return(estado de Telegram)"
    AddMsg els(GW),    els(VISTA), 42,  "return(200 OK)"
    AddMsg els(VISTA), els(ADM),   43,  "muestra las propuestas pendientes"
    ' ==============================================================
    ' Endpoint 3: POST /agentes/propuestas/{id}/aprobar
    ' ==============================================================
    AddMsg els(ADM),   els(VISTA), 44,  "resolver(propuesta, aprobar = true)"
    AddMsg els(VISTA), els(GW),    45,  "POST /agentes/propuestas/{id}/aprobar"
    AddMsg els(GW),    els(GW),    46,  "requireAuth(token)"
    AddMsg els(GW),    els(IA),    47,  "aprobar(id)"
    AddMsg els(IA),    els(IA),    48,  "decidir_desde_panel(id, aprobar)"
    AddMsg els(IA),    els(IA),    49,  "propuestas.resolver(id, aprobar)"
    AddMsg els(IA),    els(SQL),   50,  "tomar_pendiente(id, EJECUTANDO)"
    AddMsg els(SQL),   els(IA),    51,  "return(ok)"
    ' alt propuesta de menu (mensajes 52 a 61)
    AddMsg els(IA),    els(IA),    52,  "_ejecutar_menu(payload)"
    AddMsg els(IA),    els(MCP),   53,  "MCP tools/call consultar_menu(turno)"
    AddMsg els(MCP),   els(MONGO), 54,  "findBySemana(inicio, turno)"
    AddMsg els(MONGO), els(MCP),   55,  "return(menus)"
    AddMsg els(MCP),   els(IA),    56,  "return(menus existentes)"
    AddMsg els(IA),    els(MCP),   57,  "MCP tools/call publicar_menu(fecha, turno, platos)"
    AddMsg els(MCP),   els(MCP),   58,  "ArmarMenuSemanalUseCase.ejecutar(entrada)"
    AddMsg els(MCP),   els(MONGO), 59,  "save(menu)"
    AddMsg els(MONGO), els(MCP),   60,  "return(menu)"
    AddMsg els(MCP),   els(IA),    61,  "return(menuDto)"
    ' else propuesta de compra (mensajes 62 a 69)
    AddMsg els(IA),    els(IA),    62,  "_ejecutar_compra(payload, id)"
    AddMsg els(IA),    els(N8N),   63,  "POST /webhook/orden-aprobada(ordenId, proveedores)"
    AddMsg els(N8N),   els(PROV),  64,  "POST /proveedores/pagos(ordenId, proveedor, monto, detalle)"
    AddMsg els(PROV),  els(PGPAG), 65,  "guardarSiNoExiste(obligacion)"
    AddMsg els(PGPAG), els(PROV),  66,  "return(obligacion PENDIENTE)"
    AddMsg els(PROV),  els(N8N),   67,  "return(201 Created)"
    AddMsg els(N8N),   els(IA),    68,  "return({ ok: true, registradas })"
    AddMsg els(IA),    els(SQL),   69,  "encolar(orden aprobada por proveedor)"
    AddMsg els(IA),    els(SQL),   70,  "cerrar(id, EJECUTADA)"
    AddMsg els(IA),    els(SQL),   71,  "encolar(resultado)"
    AddMsg els(IA),    els(N8N),   72,  "POST /webhook/notificar(telegram, resultado)"
    AddMsg els(N8N),   els(TG),    73,  "sendMessage(chat, resultado)"
    AddMsg els(TG),    els(N8N),   74,  "return(enviado)"
    AddMsg els(N8N),   els(IA),    75,  "return({ ok: true })"
    AddMsg els(IA),    els(GW),    76,  "return({ estado: EJECUTADA, resultado })"
    AddMsg els(GW),    els(VISTA), 77,  "return(200 OK)"
    AddMsg els(VISTA), els(ADM),   78,  "muestra la propuesta ejecutada"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU05 creado (camino exitoso, 78 mensajes)." & vbCrLf & _
                   "Agrega a mano: alt propuesta de menu: mensajes 52-61; else propuesta de compra: mensajes 62-69.", 0

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
