'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU02 Armar el menu semanal
'
' Endpoint 1: POST /agentes/planificador-menu
' Endpoint 2: POST /agentes/propuestas/{id}/aprobar
' Solo el CAMINO EXITOSO (timeline limpio).
'
' Fragmentos que agregas a mano (EA no permite crearlos por script):
'   loop por cada turno: mensajes 32-35
'   loop por cada dia y turno sin menu publicado: mensajes 36-40
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
Const MCP   = 7   ' McpController (MSMenu)
Const MONGO = 8   ' BD Menu (MongoDB)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU02 - Secuencia Armar el menu semanal", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(8)
    nombres(ADM)   = "Administrador"
    nombres(VISTA) = "Vista (Backoffice)"
    nombres(GW)    = "Gateway (api-gw)"
    nombres(IA)    = "AgentesRouter (MSIA)"
    nombres(SQL)   = "BD Agentes (SQLite)"
    nombres(N8N)   = "Automatizacion (n8n)"
    nombres(FCM)   = "Notificaciones (FCM)"
    nombres(MCP)   = "McpController (MSMenu)"
    nombres(MONGO) = "BD Menu (MongoDB)"

    Dim els(8)
    Dim i
    For i = 0 To 8
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
    For i = 0 To 8
        Dim dobj
        Set dobj = oDiagram.DiagramObjects.AddNew("l=" & (40 + i * 215) & ";r=" & (210 + i * 215) & ";t=-20;b=-90", "")
        dobj.ElementID = els(i).ElementID
        dobj.Sequence = i + 1
        dobj.Update
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==============================================================
    ' Endpoint 1: POST /agentes/planificador-menu
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(ADM),   els(VISTA), 1,   "correr('planificador-menu')"
    AddMsg els(VISTA), els(GW),    2,   "POST /agentes/planificador-menu"
    AddMsg els(GW),    els(GW),    3,   "requireAuth(token)"
    AddMsg els(GW),    els(IA),    4,   "planif(mision)"
    AddMsg els(IA),    els(IA),    5,   "PlanificadorMenuAgent.run(objetivo)"
    AddMsg els(IA),    els(MCP),   6,   "MCP tools/call ver_stock_bajo"
    AddMsg els(MCP),   els(MONGO), 7,   "findAll()"
    AddMsg els(MONGO), els(MCP),   8,   "return(insumos)"
    AddMsg els(MCP),   els(IA),    9,   "return(insumos con stock bajo)"
    AddMsg els(IA),    els(MCP),   10,  "MCP tools/call lotes_por_vencer(dias = 10)"
    AddMsg els(MCP),   els(MONGO), 11,  "findAll()"
    AddMsg els(MONGO), els(MCP),   12,  "return(insumos)"
    AddMsg els(MCP),   els(IA),    13,  "return(lotes por vencer)"
    AddMsg els(IA),    els(IA),    14,  "predecir_demanda(plato, fecha)"
    AddMsg els(IA),    els(IA),    15,  "proponer_menu(propuesta)"
    AddMsg els(IA),    els(SQL),   16,  "crear_si_no_hay_vigente(propuesta)"
    AddMsg els(SQL),   els(IA),    17,  "return(propuesta PENDIENTE)"
    AddMsg els(IA),    els(N8N),   18,  "POST /webhook/notificar(push, 'Menu propuesto')"
    AddMsg els(N8N),   els(FCM),   19,  "messages:send(token, titulo, cuerpo)"
    AddMsg els(FCM),   els(N8N),   20,  "return(enviado)"
    AddMsg els(N8N),   els(IA),    21,  "return({ ok: true })"
    AddMsg els(IA),    els(GW),    22,  "return({ propuesta, propuestaMenu })"
    AddMsg els(GW),    els(VISTA), 23,  "return(200 OK)"
    AddMsg els(VISTA), els(ADM),   24,  "muestra la propuesta de menu"
    ' ==============================================================
    ' Endpoint 2: POST /agentes/propuestas/{id}/aprobar
    ' ==============================================================
    AddMsg els(ADM),   els(VISTA), 25,  "resolver(propuesta, aprobar = true)"
    AddMsg els(VISTA), els(GW),    26,  "POST /agentes/propuestas/{id}/aprobar"
    AddMsg els(GW),    els(GW),    27,  "requireAuth(token)"
    AddMsg els(GW),    els(IA),    28,  "aprobar(id)"
    AddMsg els(IA),    els(IA),    29,  "propuestas.resolver(id, aprobar)"
    AddMsg els(IA),    els(SQL),   30,  "tomar_pendiente(id, EJECUTANDO)"
    AddMsg els(SQL),   els(IA),    31,  "return(ok)"
    ' loop por cada turno (mensajes 32 a 35)
    AddMsg els(IA),    els(MCP),   32,  "MCP tools/call consultar_menu(turno)"
    AddMsg els(MCP),   els(MONGO), 33,  "findBySemana(inicio, turno)"
    AddMsg els(MONGO), els(MCP),   34,  "return(menus)"
    AddMsg els(MCP),   els(IA),    35,  "return(menus existentes)"
    ' loop por cada dia y turno sin menu publicado (mensajes 36 a 40)
    AddMsg els(IA),    els(MCP),   36,  "MCP tools/call publicar_menu(fecha, turno, platos)"
    AddMsg els(MCP),   els(MCP),   37,  "ArmarMenuSemanalUseCase.ejecutar(entrada)"
    AddMsg els(MCP),   els(MONGO), 38,  "save(menu)"
    AddMsg els(MONGO), els(MCP),   39,  "return(menu)"
    AddMsg els(MCP),   els(IA),    40,  "return(menuDto)"
    AddMsg els(IA),    els(SQL),   41,  "cerrar(id, EJECUTADA)"
    AddMsg els(SQL),   els(IA),    42,  "return(ok)"
    AddMsg els(IA),    els(GW),    43,  "return({ estado: EJECUTADA, resultado })"
    AddMsg els(GW),    els(VISTA), 44,  "return(200 OK)"
    AddMsg els(VISTA), els(ADM),   45,  "muestra el menu publicado"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU02 creado (camino exitoso, 45 mensajes)." & vbCrLf & _
                   "Agrega a mano: loop por cada turno: mensajes 32-35; loop por cada dia y turno sin menu publicado: mensajes 36-40.", 0

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
