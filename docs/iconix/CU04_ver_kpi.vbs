'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU04 Ver KPI
'
' Endpoint: GET /ml/kpis
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
Const ANAL  = 5   ' AnaliticaController (MSReservas)
Const ESTC  = 6   ' EstudiantesController (MSReservas)
Const PGRES = 7   ' BD Reservas (PostgreSQL)
Const PAG   = 8   ' PagosController (MSPagos)
Const PGPAG = 9   ' BD Pagos (PostgreSQL)
Const CTRL  = 10  ' MenuController (MSMenu)
Const INS   = 11  ' InsumoController (MSMenu)
Const MONGO = 12  ' BD Menu (MongoDB)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU04 - Secuencia Ver KPI", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(12)
    nombres(ADM)   = "Administrador"
    nombres(VISTA) = "Vista (BI)"
    nombres(GW)    = "Gateway (api-gw)"
    nombres(IA)    = "PrediccionesRouter (MSIA)"
    nombres(SQL)   = "BD Agentes (SQLite)"
    nombres(ANAL)  = "AnaliticaController (MSReservas)"
    nombres(ESTC)  = "EstudiantesController (MSReservas)"
    nombres(PGRES) = "BD Reservas (PostgreSQL)"
    nombres(PAG)   = "PagosController (MSPagos)"
    nombres(PGPAG) = "BD Pagos (PostgreSQL)"
    nombres(CTRL)  = "MenuController (MSMenu)"
    nombres(INS)   = "InsumoController (MSMenu)"
    nombres(MONGO) = "BD Menu (MongoDB)"

    Dim els(12)
    Dim i
    For i = 0 To 12
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
    For i = 0 To 12
        Dim dobj
        Set dobj = oDiagram.DiagramObjects.AddNew("l=" & (40 + i * 215) & ";r=" & (210 + i * 215) & ";t=-20;b=-90", "")
        dobj.ElementID = els(i).ElementID
        dobj.Sequence = i + 1
        dobj.Update
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==============================================================
    ' Endpoint: GET /ml/kpis
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(ADM),   els(VISTA), 1,   "abrir KPI"
    AddMsg els(VISTA), els(GW),    2,   "GET /ml/kpis"
    AddMsg els(GW),    els(GW),    3,   "requireAuth(token)"
    AddMsg els(GW),    els(IA),    4,   "indicadores()"
    AddMsg els(IA),    els(IA),    5,   "kpis.calcular()"
    AddMsg els(IA),    els(IA),    6,   "KPI 1: _ocupacion(hoy)"
    AddMsg els(IA),    els(CTRL),  7,   "historial(desde, hasta)"
    AddMsg els(CTRL),  els(MONGO), 8,   "findByRango(desde, hasta)"
    AddMsg els(MONGO), els(CTRL),  9,   "return(menus)"
    AddMsg els(CTRL),  els(IA),    10,  "return(menus con cupo y apartadas)"
    AddMsg els(IA),    els(IA),    11,  "KPI 2: _ingresos(hoy)"
    AddMsg els(IA),    els(PAG),   12,  "listar()"
    AddMsg els(PAG),   els(PGPAG), 13,  "todos()"
    AddMsg els(PGPAG), els(PAG),   14,  "return(pagos)"
    AddMsg els(PAG),   els(IA),    15,  "return(pagos)"
    AddMsg els(IA),    els(IA),    16,  "KPI 3: _volumen(hoy)"
    AddMsg els(IA),    els(ANAL),  17,  "listarReservas()"
    AddMsg els(ANAL),  els(PGRES), 18,  "listarTodas()"
    AddMsg els(PGRES), els(ANAL),  19,  "return(reservas)"
    AddMsg els(ANAL),  els(IA),    20,  "return(reservas)"
    AddMsg els(IA),    els(IA),    21,  "KPI 4: _cancelacion()"
    AddMsg els(IA),    els(IA),    22,  "KPI 5: _becas()"
    AddMsg els(IA),    els(ANAL),  23,  "listarBecas()"
    AddMsg els(ANAL),  els(PGRES), 24,  "listarTodas()"
    AddMsg els(PGRES), els(ANAL),  25,  "return(becas)"
    AddMsg els(ANAL),  els(IA),    26,  "return(becas)"
    AddMsg els(IA),    els(ESTC),  27,  "listar()"
    AddMsg els(ESTC),  els(PGRES), 28,  "listar()"
    AddMsg els(PGRES), els(ESTC),  29,  "return(estudiantes)"
    AddMsg els(ESTC),  els(IA),    30,  "return(estudiantes)"
    AddMsg els(IA),    els(IA),    31,  "KPI 6: _desperdicio()"
    AddMsg els(IA),    els(SQL),   32,  "todas_las_bandejas()"
    AddMsg els(SQL),   els(IA),    33,  "return(bandejas)"
    AddMsg els(IA),    els(IA),    34,  "KPI 7: _insumos()"
    AddMsg els(IA),    els(INS),   35,  "listar()"
    AddMsg els(INS),   els(MONGO), 36,  "findAll()"
    AddMsg els(MONGO), els(INS),   37,  "return(insumos)"
    AddMsg els(INS),   els(IA),    38,  "return(insumos)"
    AddMsg els(IA),    els(IA),    39,  "_registros()"
    AddMsg els(IA),    els(GW),    40,  "return({ generado, kpis, registros })"
    AddMsg els(GW),    els(VISTA), 41,  "return(200 OK)"
    AddMsg els(VISTA), els(ADM),   42,  "muestra los 7 KPI con su estado y grafico"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU04 creado (camino exitoso, 42 mensajes).", 0

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
