'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU07 Predecir la demanda
'
' Endpoint 1: GET /ml/regresion
' Endpoint 2: POST /ml/demanda
' Solo el CAMINO EXITOSO (timeline limpio).
'
' Fragmentos que agregas a mano (EA no permite crearlos por script):
'   opt si cambiaron los datos: mensajes 12-12
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
Const CTRL  = 4   ' MenuController (MSMenu)
Const MONGO = 5   ' BD Menu (MongoDB)
Const CLIMA = 6   ' API Clima (Open-Meteo)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU07 - Secuencia Predecir la demanda", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(6)
    nombres(ADM)   = "Administrador"
    nombres(VISTA) = "Vista (BI)"
    nombres(GW)    = "Gateway (api-gw)"
    nombres(IA)    = "PrediccionesRouter (MSIA)"
    nombres(CTRL)  = "MenuController (MSMenu)"
    nombres(MONGO) = "BD Menu (MongoDB)"
    nombres(CLIMA) = "API Clima (OpenMeteo)"

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
    ' Endpoint 1: GET /ml/regresion
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(ADM),   els(VISTA), 1,   "abrir Prediccion de demanda"
    AddMsg els(VISTA), els(GW),    2,   "GET /ml/regresion"
    AddMsg els(GW),    els(GW),    3,   "requireAuth(token)"
    AddMsg els(GW),    els(IA),    4,   "regresion_estado()"
    AddMsg els(IA),    els(IA),    5,   "regresion.estado()"
    AddMsg els(IA),    els(CTRL),  6,   "historial(desde, hasta)"
    AddMsg els(CTRL),  els(MONGO), 7,   "findByRango(desde, hasta)"
    AddMsg els(MONGO), els(CTRL),  8,   "return(menus)"
    AddMsg els(CTRL),  els(IA),    9,   "return(menus con cupo y apartadas)"
    AddMsg els(IA),    els(CLIMA), 10,  "temperatura_diaria(lat, lon)"
    AddMsg els(CLIMA), els(IA),    11,  "return(temperaturas)"
    ' opt si cambiaron los datos (mensajes 12 a 12)
    AddMsg els(IA),    els(IA),    12,  "_entrenar() con RandomForestRegressor"
    AddMsg els(IA),    els(IA),    13,  "_predecir(fecha, turno, plato, cupo) por cada menu futuro"
    AddMsg els(IA),    els(GW),    14,  "return({ metricas, importancias, serie, plan })"
    AddMsg els(GW),    els(VISTA), 15,  "return(200 OK)"
    AddMsg els(VISTA), els(ADM),   16,  "muestra metricas y plan de cocina"
    ' ==============================================================
    ' Endpoint 2: POST /ml/demanda
    ' ==============================================================
    AddMsg els(ADM),   els(VISTA), 17,  "predecir(plato, fecha, turno)"
    AddMsg els(VISTA), els(GW),    18,  "POST /ml/demanda"
    AddMsg els(GW),    els(GW),    19,  "requireAuth(token)"
    AddMsg els(GW),    els(IA),    20,  "demanda(dto)"
    AddMsg els(IA),    els(IA),    21,  "regresion.predecir(fecha, plato, turno)"
    AddMsg els(IA),    els(IA),    22,  "_predecir(fecha, turno, plato, cupo)"
    AddMsg els(IA),    els(GW),    23,  "return({ racionesEstimadas, diaSemana, esFeriado, temperatura })"
    AddMsg els(GW),    els(VISTA), 24,  "return(200 OK)"
    AddMsg els(VISTA), els(ADM),   25,  "muestra las raciones estimadas"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU07 creado (camino exitoso, 25 mensajes)." & vbCrLf & _
                   "Agrega a mano: opt si cambiaron los datos: mensajes 12-12.", 0

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
