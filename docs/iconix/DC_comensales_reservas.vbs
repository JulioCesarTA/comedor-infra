'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE CLASES - Base de Datos comensales_reservas
'
' Cada tabla es una clase: atributos (-) = columnas, metodos (+) = reglas
' de negocio de la clase. Relaciones con nombre y multiplicidad.
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

Dim clsEstudiante
Dim clsBeca
Dim clsReserva
Dim clsAsistencia
Dim clsTurno

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Clases ----------
    Set oDiagram = oPackage.Diagrams.AddNew("DC - Base de Datos comensales_reservas", "Class")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ==============================================================
    ' Estudiante   <- tabla estudiantes
    ' ==============================================================
    Set clsEstudiante = NuevaClase("Estudiante", "Class")
    AddAttr clsEstudiante, "id", "uuid", 0
    AddAttr clsEstudiante, "registroUniv", "string", 1
    AddAttr clsEstudiante, "nombre", "string", 2
    AddAttr clsEstudiante, "email", "string", 3
    AddAttr clsEstudiante, "telefono", "string", 4
    AddMet clsEstudiante, "Estudiante", "", "id:uuid,registroUniv:string,nombre:string,email:string,telefono:string", False, 0
    AddMet clsEstudiante, "save", "Estudiante", "e:Estudiante", False, 1
    AddMet clsEstudiante, "findById", "Estudiante", "id:uuid", False, 2
    AddMet clsEstudiante, "findByRegistro", "Estudiante", "registro:string", False, 3
    AddMet clsEstudiante, "listar", "Estudiante[]", "", False, 4

    ' ==============================================================
    ' Beca   <- tabla becas
    ' ==============================================================
    Set clsBeca = NuevaClase("Beca", "Class")
    AddAttr clsBeca, "id", "uuid", 0
    AddAttr clsBeca, "estudianteId", "uuid", 1
    AddAttr clsBeca, "tipo", "string", 2
    AddAttr clsBeca, "cupoRacionesMes", "int", 3
    AddAttr clsBeca, "racionesUsadasMes", "int", 4
    AddAttr clsBeca, "vigenteDesde", "timestamp", 5
    AddAttr clsBeca, "vigenteHasta", "timestamp", 6
    AddMet clsBeca, "estaVigente", "bool", "hoy:date", False, 0
    AddMet clsBeca, "tieneCupo", "bool", "", False, 1
    AddMet clsBeca, "cubreRacion", "bool", "hoy:date", False, 2
    AddMet clsBeca, "save", "Beca", "b:Beca", False, 3
    AddMet clsBeca, "findActivaByEstudiante", "Beca", "estudianteId:uuid", False, 4
    AddMet clsBeca, "listarTodas", "Beca[]", "", False, 5

    ' ==============================================================
    ' Reserva   <- tabla reservas
    ' ==============================================================
    Set clsReserva = NuevaClase("Reserva", "Class")
    AddAttr clsReserva, "id", "uuid", 0
    AddAttr clsReserva, "estudianteId", "uuid", 1
    AddAttr clsReserva, "menuId", "string", 2
    AddAttr clsReserva, "platoId", "string", 3
    AddAttr clsReserva, "fecha", "date", 4
    AddAttr clsReserva, "turno", "Turno", 5
    AddAttr clsReserva, "estado", "string", 6
    AddAttr clsReserva, "qrCode", "string", 7
    AddAttr clsReserva, "createdAt", "timestamp", 8
    AddMet clsReserva, "confirmar", "void", "qr:string", False, 0
    AddMet clsReserva, "cancelar", "void", "", False, 1
    AddMet clsReserva, "marcarConsumida", "void", "", False, 2
    AddMet clsReserva, "save", "Reserva", "r:Reserva", False, 3
    AddMet clsReserva, "findById", "Reserva", "id:uuid", False, 4
    AddMet clsReserva, "findByEstudiante", "Reserva[]", "estudianteId:uuid", False, 5
    AddMet clsReserva, "listarTodas", "Reserva[]", "", False, 6

    ' ==============================================================
    ' Asistencia   <- tabla asistencias
    ' ==============================================================
    Set clsAsistencia = NuevaClase("Asistencia", "Class")
    AddAttr clsAsistencia, "id", "uuid", 0
    AddAttr clsAsistencia, "usuario", "string", 1
    AddAttr clsAsistencia, "rol", "string", 2
    AddAttr clsAsistencia, "tipo", "string", 3
    AddAttr clsAsistencia, "lat", "float", 4
    AddAttr clsAsistencia, "lon", "float", 5
    AddAttr clsAsistencia, "distanciaM", "int", 6
    AddAttr clsAsistencia, "dentro", "bool", 7
    AddAttr clsAsistencia, "simulada", "bool", 8
    AddAttr clsAsistencia, "marcadaEn", "timestamp", 9
    AddAttr clsAsistencia, "registradaEn", "timestamp", 10
    AddMet clsAsistencia, "distancia", "int", "lat1:float,lon1:float,lat2:float,lon2:float", True, 0
    AddMet clsAsistencia, "sospechosa", "bool", "", False, 1
    AddMet clsAsistencia, "save", "Asistencia", "a:Asistencia", False, 2
    AddMet clsAsistencia, "ultimaDe", "Asistencia", "usuario:string", False, 3
    AddMet clsAsistencia, "listarDe", "Asistencia[]", "usuario:string,limite:int", False, 4
    AddMet clsAsistencia, "listarTodas", "Asistencia[]", "", False, 5

    ' ==============================================================
    ' Turno   <- enum usado por reservas.turno
    ' ==============================================================
    Set clsTurno = NuevaClase("Turno", "Enumeration")
    AddLiteral clsTurno, "DESAYUNO", 0
    AddLiteral clsTurno, "ALMUERZO", 1
    AddLiteral clsTurno, "CENA", 2

    ' ---------- Relaciones ----------
    ' AddRel origen, destino, nombre, multiplicidad origen, multiplicidad destino
    AddRel clsEstudiante, clsBeca, "tiene", "1", "*"
    AddRel clsEstudiante, clsReserva, "realiza", "1", "*"
    AddRel clsReserva, clsTurno, "es del", "*", "1"

    ' ---------- Colocar en el diagrama (t y b negativos en EA) ----------
    AddObj clsEstudiante, 380, 700, -20, -290, 1
    AddObj clsTurno, 820, 980, -40, -160, 2
    AddObj clsBeca, 20, 330, -370, -700, 3
    AddObj clsReserva, 380, 700, -370, -760, 4
    AddObj clsAsistencia, 760, 1070, -370, -780, 5
    oDiagram.DiagramObjects.Refresh

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama de clases 'comensales_reservas' creado (4 clases + enum Turno).", 0

End Sub

'------------------------------------------------------------------
' Crea una clase (o enum) en el paquete
'------------------------------------------------------------------
Function NuevaClase(sNombre, sTipo)
    Dim el
    Set el = oPackage.Elements.AddNew(sNombre, sTipo)
    el.Update
    oPackage.Elements.Refresh
    Set NuevaClase = el
End Function

'------------------------------------------------------------------
' Atributo privado (-) en el orden de la tabla
'------------------------------------------------------------------
Sub AddAttr(oClase, sNombre, sTipo, nPos)
    Dim a
    Set a = oClase.Attributes.AddNew(sNombre, sTipo)
    a.Visibility = "Private"
    a.Pos = nPos
    a.Update
    oClase.Attributes.Refresh
End Sub

'------------------------------------------------------------------
' Valor de un enum
'------------------------------------------------------------------
Sub AddLiteral(oEnum, sNombre, nPos)
    Dim a
    Set a = oEnum.Attributes.AddNew(sNombre, "")
    a.Visibility = "Public"
    a.Pos = nPos
    a.Update
    oEnum.Attributes.Refresh
End Sub

'------------------------------------------------------------------
' Metodo publico (+) con parametros "nombre:tipo,nombre:tipo"
'   El metodo se guarda ANTES de agregarle parametros.
'------------------------------------------------------------------
Sub AddMet(oClase, sNombre, sRetorno, sParams, bStatic, nPos)
    Dim m, p, partes, i, par
    Set m = oClase.Methods.AddNew(sNombre, sRetorno)
    m.Visibility = "Public"
    m.IsStatic = bStatic
    m.Pos = nPos
    m.Update

    If sParams <> "" Then
        partes = Split(sParams, ",")
        For i = 0 To UBound(partes)
            par = Split(partes(i), ":")
            Set p = m.Parameters.AddNew(Trim(par(0)), Trim(par(1)))
            p.Kind = "in"
            p.Position = i
            p.Update
        Next
        m.Parameters.Refresh
    End If

    m.Update
    oClase.Methods.Refresh
End Sub

'------------------------------------------------------------------
' Asociacion con nombre y multiplicidad en cada extremo
'------------------------------------------------------------------
Sub AddRel(oOrigen, oDestino, sNombre, sMultOrigen, sMultDestino)
    Dim con
    Set con = oOrigen.Connectors.AddNew(sNombre, "Association")
    con.SupplierID = oDestino.ElementID
    con.ClientEnd.Cardinality = sMultOrigen
    con.SupplierEnd.Cardinality = sMultDestino
    con.Update
    oOrigen.Connectors.Refresh
End Sub

'------------------------------------------------------------------
' Coloca un elemento en el diagrama
'------------------------------------------------------------------
Sub AddObj(oElem, l, r, t, b, nSeq)
    Dim dobj
    Set dobj = oDiagram.DiagramObjects.AddNew("l=" & l & ";r=" & r & ";t=" & t & ";b=" & b & ";", "")
    dobj.ElementID = oElem.ElementID
    dobj.Sequence = nSeq
    dobj.Update
End Sub

Main
