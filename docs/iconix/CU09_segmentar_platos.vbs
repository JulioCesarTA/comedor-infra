'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU09 Segmentar platos
'
' Endpoint: GET /ml/agrupar-platos
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
Const ADM   = 0   ' Administrador
Const VISTA = 1   ' Vista (BI)
Const GW    = 2   ' Gateway (REST)
Const IA    = 3   ' PrediccionesRouter (MSIA)
Const SQL   = 4   ' BD Agentes (SQLite)
Const CTRL  = 5   ' MenuController (MSMenu)
Const MONGO = 6   ' BD Menu (MongoDB)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU09 - Secuencia Segmentar platos", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(6)
    nombres(ADM)   = "Administrador"
    nombres(VISTA) = "Vista (BI)"
    nombres(GW)    = "Gateway (api-gw)"
    nombres(IA)    = "PrediccionesRouter (MSIA)"
    nombres(SQL)   = "BD Agentes (SQLite)"
    nombres(CTRL)  = "MenuController (MSMenu)"
    nombres(MONGO) = "BD Menu (MongoDB)"

    Dim els(6)
    Dim i
    For i = 0 To 6
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
    For i = 0 To 6
        Dim dobj
        Set dobj = oDiagram.DiagramObjects.AddNew("l=" & (40 + i * 215) & ";r=" & (210 + i * 215) & ";t=-20;b=-90", "")
        dobj.ElementID = els(i).ElementID
        dobj.Sequence = i + 1
        dobj.Update
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==============================================================
    ' Endpoint: GET /ml/agrupar-platos
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(ADM),   els(VISTA), 1,   "abrir Agrupacion de platos"
    AddMsg els(VISTA), els(GW),    2,   "GET /ml/agrupar-platos"
    AddMsg els(GW),    els(GW),    3,   "requireAuth(token)"
    AddMsg els(GW),    els(IA),    4,   "agrupar_platos()"
    AddMsg els(IA),    els(IA),    5,   "agrupamiento.calcular()"
    AddMsg els(IA),    els(CTRL),  6,   "historial(desde, hasta)"
    AddMsg els(CTRL),  els(MONGO), 7,   "findByRango(desde, hasta)"
    AddMsg els(MONGO), els(CTRL),  8,   "return(menus)"
    AddMsg els(CTRL),  els(IA),    9,   "return(menus con cupo y apartadas)"
    AddMsg els(IA),    els(SQL),   10,  "restante_medio_por_plato(3)"
    AddMsg els(SQL),   els(IA),    11,  "return(desperdicio por plato)"
    AddMsg els(IA),    els(IA),    12,  "StandardScaler.fit_transform(X)"
    AddMsg els(IA),    els(IA),    13,  "KMeans.fit_predict(Z) y silhouette_score(Z, lab)"
    AddMsg els(IA),    els(IA),    14,  "asigna Mantener, Ajustar o Retirar a cada grupo"
    AddMsg els(IA),    els(GW),    15,  "return({ k, silueta, grupos, puntos })"
    AddMsg els(GW),    els(VISTA), 16,  "return(200 OK)"
    AddMsg els(VISTA), els(ADM),   17,  "muestra los grupos y el mapa de platos"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU09 creado (camino exitoso, 17 mensajes).", 0

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
