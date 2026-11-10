'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU08 Generar reportes
'
' Endpoint: GET /reportes/snapshot (copia de datos para trabajar sin internet)
' Generar el reporte (en el navegador, sin llamar al servidor)
' Solo el CAMINO EXITOSO (timeline limpio).
'
' Fragmentos que agregas a mano (EA no permite crearlos por script):
'   opt no hay copia o tiene mas de 15 minutos, y hay internet: mensajes 4-40
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
Const LOCAL = 2   ' BD Local (IndexedDB)
Const GW    = 3   ' Gateway (REST)
Const IA    = 4   ' ReportesRouter (MSIA)
Const ANAL  = 5   ' AnaliticaController (MSReservas)
Const ESTC  = 6   ' EstudiantesController (MSReservas)
Const PGRES = 7   ' BD Reservas (PostgreSQL)
Const PAG   = 8   ' PagosController (MSPagos)
Const PGPAG = 9   ' BD Pagos (PostgreSQL)
Const CTRL  = 10  ' MenuController (MSMenu)
Const INS   = 11  ' InsumoController (MSMenu)
Const MONGO = 12  ' BD Menu (MongoDB)
Const SQL   = 13  ' BD Agentes (SQLite)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU08 - Secuencia Generar reportes", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(13)
    nombres(ADM)   = "Administrador"
    nombres(VISTA) = "Vista (BI)"
    nombres(LOCAL) = "BD Local (IndexedDB)"
    nombres(GW)    = "Gateway (api-gw)"
    nombres(IA)    = "ReportesRouter (MSIA)"
    nombres(ANAL)  = "AnaliticaController (MSReservas)"
    nombres(ESTC)  = "EstudiantesController (MSReservas)"
    nombres(PGRES) = "BD Reservas (PostgreSQL)"
    nombres(PAG)   = "PagosController (MSPagos)"
    nombres(PGPAG) = "BD Pagos (PostgreSQL)"
    nombres(CTRL)  = "MenuController (MSMenu)"
    nombres(INS)   = "InsumoController (MSMenu)"
    nombres(MONGO) = "BD Menu (MongoDB)"
    nombres(SQL)   = "BD Agentes (SQLite)"

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
    ' Endpoint: GET /reportes/snapshot (copia de datos para trabajar sin internet)
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(ADM),   els(VISTA), 1,   "abrir Reportes"
    AddMsg els(VISTA), els(LOCAL), 2,   "leerGuardado('snapshot')"
    AddMsg els(LOCAL), els(VISTA), 3,   "return(copia guardada)"
    ' opt no hay copia o tiene mas de 15 minutos, y hay internet (mensajes 4 a 40)
    AddMsg els(VISTA), els(GW),    4,   "GET /reportes/snapshot"
    AddMsg els(GW),    els(GW),    5,   "requireAuth(token)"
    AddMsg els(GW),    els(IA),    6,   "get_snapshot(roles)"
    AddMsg els(IA),    els(IA),    7,   "snapshot.construir(roles)"
    AddMsg els(IA),    els(ANAL),  8,   "listarReservas()"
    AddMsg els(ANAL),  els(PGRES), 9,   "listarTodas()"
    AddMsg els(PGRES), els(ANAL),  10,  "return(reservas)"
    AddMsg els(ANAL),  els(IA),    11,  "return(reservas)"
    AddMsg els(IA),    els(PAG),   12,  "listar()"
    AddMsg els(PAG),   els(PGPAG), 13,  "todos()"
    AddMsg els(PGPAG), els(PAG),   14,  "return(pagos)"
    AddMsg els(PAG),   els(IA),    15,  "return(pagos)"
    AddMsg els(IA),    els(ESTC),  16,  "listar()"
    AddMsg els(ESTC),  els(PGRES), 17,  "listar()"
    AddMsg els(PGRES), els(ESTC),  18,  "return(estudiantes)"
    AddMsg els(ESTC),  els(IA),    19,  "return(estudiantes)"
    AddMsg els(IA),    els(ANAL),  20,  "listarBecas()"
    AddMsg els(ANAL),  els(PGRES), 21,  "listarTodas()"
    AddMsg els(PGRES), els(ANAL),  22,  "return(becas)"
    AddMsg els(ANAL),  els(IA),    23,  "return(becas)"
    AddMsg els(IA),    els(CTRL),  24,  "historial(desde, hasta)"
    AddMsg els(CTRL),  els(MONGO), 25,  "findByRango(desde, hasta)"
    AddMsg els(MONGO), els(CTRL),  26,  "return(menus)"
    AddMsg els(CTRL),  els(IA),    27,  "return(menus)"
    AddMsg els(IA),    els(INS),   28,  "listar()"
    AddMsg els(INS),   els(MONGO), 29,  "findAll()"
    AddMsg els(MONGO), els(INS),   30,  "return(insumos)"
    AddMsg els(INS),   els(IA),    31,  "return(insumos)"
    AddMsg els(IA),    els(SQL),   32,  "todas_las_bandejas()"
    AddMsg els(SQL),   els(IA),    33,  "return(bandejas)"
    AddMsg els(IA),    els(ANAL),  34,  "listarAsistencia()"
    AddMsg els(ANAL),  els(PGRES), 35,  "listarTodas()"
    AddMsg els(PGRES), els(ANAL),  36,  "return(marcas)"
    AddMsg els(ANAL),  els(IA),    37,  "return(asistencia)"
    AddMsg els(IA),    els(GW),    38,  "return({ datasets, catalogo, generado })"
    AddMsg els(GW),    els(VISTA), 39,  "return(200 OK)"
    AddMsg els(VISTA), els(LOCAL), 40,  "guardar('snapshot', copia)"
    AddMsg els(VISTA), els(ADM),   41,  "muestra 'IA local, datos del ...'"
    ' ==============================================================
    ' Generar el reporte (en el navegador, sin llamar al servidor)
    ' ==============================================================
    AddMsg els(ADM),   els(VISTA), 42,  "generar(texto o voz)"
    AddMsg els(VISTA), els(VISTA), 43,  "lenguaje.interpretar(texto, previa, tablas)"
    AddMsg els(VISTA), els(VISTA), 44,  "motor.ejecutar(spec, tablas)"
    AddMsg els(VISTA), els(LOCAL), 45,  "guardar('ultimo', reporte)"
    AddMsg els(VISTA), els(ADM),   46,  "muestra tabla, grafico y resumen"
    AddMsg els(ADM),   els(VISTA), 47,  "bajar(reporte, 'pdf' o 'excel')"
    AddMsg els(VISTA), els(VISTA), 48,  "exportar(reporte, formato)"
    AddMsg els(VISTA), els(ADM),   49,  "descarga el archivo"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU08 creado (camino exitoso, 49 mensajes)." & vbCrLf & _
                   "Agrega a mano: opt no hay copia o tiene mas de 15 minutos, y hay internet: mensajes 4-40.", 0

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
