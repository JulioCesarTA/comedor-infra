'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE SECUENCIA - CU06 Analizar el desperdicio con foto de bandeja
'
' Analisis en el telefono (funciona sin internet)
' Endpoint 1 (con internet): GET /ml/vision/paquete-movil
' Endpoint 2 (con internet): POST /ml/vision/subida
' Endpoint 3 (con internet): POST /ml/vision/bandeja-movil
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
Const VISTA = 1   ' Vista (App Movil)
Const TFL   = 2   ' IA Local (TensorFlow Lite)
Const LOCAL = 3   ' BD Local (Archivos del telefono)
Const GW    = 4   ' Gateway (REST)
Const IA    = 5   ' PrediccionesRouter (MSIA)
Const S3    = 6   ' Bucket (S3)
Const SQL   = 7   ' BD Agentes (SQLite)

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Secuencia ----------
    Set oDiagram = oPackage.Diagrams.AddNew("CU06 - Secuencia Analizar el desperdicio con foto de bandeja", "Sequence")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ---------- Crear los participantes (lifelines) ----------
    Dim nombres(7)
    nombres(CAJA)  = "Personal de Caja"
    nombres(VISTA) = "Vista (App Movil)"
    nombres(TFL)   = "IA Local (TFLite)"
    nombres(LOCAL) = "BD Local (Archivos)"
    nombres(GW)    = "Gateway (api-gw)"
    nombres(IA)    = "PrediccionesRouter (MSIA)"
    nombres(S3)    = "Bucket (S3)"
    nombres(SQL)   = "BD Agentes (SQLite)"

    Dim els(7)
    Dim i
    For i = 0 To 7
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
    For i = 0 To 7
        Dim dobj
        Set dobj = oDiagram.DiagramObjects.AddNew("l=" & (40 + i * 215) & ";r=" & (210 + i * 215) & ";t=-20;b=-90", "")
        dobj.ElementID = els(i).ElementID
        dobj.Sequence = i + 1
        dobj.Update
    Next
    oDiagram.DiagramObjects.Refresh

    ' ==============================================================
    ' Analisis en el telefono (funciona sin internet)
    ' ==============================================================
    ' AddMsg origen, destino, numero, texto
    AddMsg els(CAJA),  els(VISTA), 1,   "_procesar('bandeja', foto)"
    AddMsg els(VISTA), els(VISTA), 2,   "prepararFoto(bytes)"
    AddMsg els(VISTA), els(TFL),   3,   "caracteristicas(rgba)"
    AddMsg els(TFL),   els(VISTA), 4,   "return(mapa)"
    AddMsg els(VISTA), els(LOCAL), 5,   "guardarFoto(jpeg, id)"
    AddMsg els(LOCAL), els(VISTA), 6,   "return(foto)"
    AddMsg els(VISTA), els(VISTA), 7,   "analizarBandeja(rgba, mapa, referencia)"
    AddMsg els(VISTA), els(LOCAL), 8,   "guardarEstado(bandeja pendiente)"
    AddMsg els(VISTA), els(CAJA),  9,   "muestra % restante y % comido"
    ' ==============================================================
    ' Endpoint 1 (con internet): GET /ml/vision/paquete-movil
    ' ==============================================================
    AddMsg els(VISTA), els(VISTA), 10,  "sincronizar(estado, api)"
    AddMsg els(VISTA), els(GW),    11,  "GET /ml/vision/paquete-movil"
    AddMsg els(GW),    els(GW),    12,  "requireAuth(token)"
    AddMsg els(GW),    els(IA),    13,  "vision_paquete_movil(limite)"
    AddMsg els(IA),    els(SQL),   14,  "referencias(limite)"
    AddMsg els(SQL),   els(IA),    15,  "return(referencias)"
    AddMsg els(IA),    els(GW),    16,  "return({ referencias })"
    AddMsg els(GW),    els(VISTA), 17,  "return(200 OK)"
    ' ==============================================================
    ' Endpoint 2 (con internet): POST /ml/vision/subida
    ' ==============================================================
    AddMsg els(VISTA), els(GW),    18,  "POST /ml/vision/subida"
    AddMsg els(GW),    els(GW),    19,  "requireAuth(token)"
    AddMsg els(GW),    els(IA),    20,  "vision_subida(tipo, clienteId, fecha)"
    AddMsg els(IA),    els(IA),    21,  "vision.url_subida(tipo, clienteId, fecha)"
    AddMsg els(IA),    els(GW),    22,  "return({ clave, url, encabezados })"
    AddMsg els(GW),    els(VISTA), 23,  "return(200 OK)"
    AddMsg els(VISTA), els(S3),    24,  "PUT foto (URL temporal)"
    AddMsg els(S3),    els(VISTA), 25,  "return(200 OK)"
    ' ==============================================================
    ' Endpoint 3 (con internet): POST /ml/vision/bandeja-movil
    ' ==============================================================
    AddMsg els(VISTA), els(GW),    26,  "POST /ml/vision/bandeja-movil"
    AddMsg els(GW),    els(GW),    27,  "requireAuth(token)"
    AddMsg els(GW),    els(IA),    28,  "vision_bandeja_movil(dto)"
    AddMsg els(IA),    els(IA),    29,  "vision.registrar_bandeja_movil(dto)"
    AddMsg els(IA),    els(SQL),   30,  "por_cliente('bandejas', clienteId)"
    AddMsg els(SQL),   els(IA),    31,  "return(sin registro previo)"
    AddMsg els(IA),    els(SQL),   32,  "referencia(refId)"
    AddMsg els(SQL),   els(IA),    33,  "return(referencia)"
    AddMsg els(IA),    els(S3),    34,  "existe(fotoKey)"
    AddMsg els(S3),    els(IA),    35,  "return(true)"
    AddMsg els(IA),    els(SQL),   36,  "guardar_bandeja(bid, refId, plato, restante, comido, confianza)"
    AddMsg els(IA),    els(GW),    37,  "return({ id, repetido: false })"
    AddMsg els(GW),    els(VISTA), 38,  "return(200 OK)"
    AddMsg els(VISTA), els(LOCAL), 39,  "guardarEstado(bandeja enviada)"

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama CU06 creado (camino exitoso, 39 mensajes).", 0

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
