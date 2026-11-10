'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE CLASES - Base de Datos pagos_tickets
'
' Cada tabla es una clase: atributos (-) = columnas, metodos (+) = reglas
' de negocio de la clase y metodos del repositorio que guarda/lee la tabla.
' Relaciones con nombre y multiplicidad.
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

Dim clsPago
Dim clsTicket
Dim clsProveedor
Dim clsObligacion
Dim clsMetodo
Dim clsEstado

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Clases ----------
    Set oDiagram = oPackage.Diagrams.AddNew("DC - Base de Datos pagos_tickets", "Class")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ==============================================================
    ' Pago   <- tabla pagos
    ' ==============================================================
    Set clsPago = NuevaClase("Pago", "Class")
    AddAttr clsPago, "id", "uuid", 0
    AddAttr clsPago, "reserva_id", "uuid", 1
    AddAttr clsPago, "estudiante_id", "uuid", 2
    AddAttr clsPago, "monto", "decimal", 3
    AddAttr clsPago, "metodo", "MetodoPago", 4
    AddAttr clsPago, "estado", "EstadoPago", 5
    AddAttr clsPago, "referencia_pasarela", "string", 6
    AddAttr clsPago, "created_at", "timestamp", 7
    AddMet clsPago, "nuevo", "Pago", "id:uuid,reservaId:uuid,estudianteId:uuid,monto:decimal,metodo:MetodoPago,createdAt:timestamp", True, 0
    AddMet clsPago, "cobrar", "void", "ticketId:uuid", False, 1
    AddMet clsPago, "asociarReferenciaPasarela", "void", "referencia:string", False, 2
    AddMet clsPago, "requiereDevolucionEnPasarela", "bool", "", False, 3
    AddMet clsPago, "fallar", "void", "", False, 4
    AddMet clsPago, "devolver", "void", "", False, 5
    AddMet clsPago, "save", "void", "pago:Pago", False, 6
    AddMet clsPago, "findById", "Pago", "id:uuid", False, 7
    AddMet clsPago, "todos", "Pago[]", "", False, 8
    AddMet clsPago, "delEstudiante", "Pago[]", "estudianteId:uuid", False, 9

    ' ==============================================================
    ' Ticket   <- tabla tickets
    ' ==============================================================
    Set clsTicket = NuevaClase("Ticket", "Class")
    AddAttr clsTicket, "id", "uuid", 0
    AddAttr clsTicket, "pago_id", "uuid", 1
    AddAttr clsTicket, "emitido_en", "timestamp", 2
    AddMet clsTicket, "Ticket", "", "id:uuid,pagoId:uuid,reservaId:uuid,monto:decimal,emitidoEn:timestamp", False, 0
    AddMet clsTicket, "save", "void", "t:Ticket", False, 1
    AddMet clsTicket, "findById", "Ticket", "id:uuid", False, 2

    ' ==============================================================
    ' Proveedor   <- tabla proveedores (PROPUESTA: hoy no existe)
    ' ==============================================================
    Set clsProveedor = NuevaClase("Proveedor", "Class")
    AddAttr clsProveedor, "id", "uuid", 0
    AddAttr clsProveedor, "nombre", "string", 1
    AddMet clsProveedor, "registrar", "Proveedor", "nombre:string", False, 0
    AddMet clsProveedor, "buscarPorNombre", "Proveedor", "nombre:string", False, 1
    AddMet clsProveedor, "listar", "Proveedor[]", "", False, 2

    ' ==============================================================
    ' ObligacionProveedor   <- tabla obligaciones_proveedor
    ' ==============================================================
    Set clsObligacion = NuevaClase("ObligacionProveedor", "Class")
    AddAttr clsObligacion, "id", "uuid", 0
    AddAttr clsObligacion, "orden_id", "string", 1
    AddAttr clsObligacion, "proveedor_id", "uuid", 2
    AddAttr clsObligacion, "monto", "decimal", 3
    AddAttr clsObligacion, "detalle", "json", 4
    AddAttr clsObligacion, "estado", "string", 5
    AddAttr clsObligacion, "creada_en", "timestamp", 6
    AddMet clsObligacion, "ObligacionProveedor", "", "id:uuid,ordenId:string,proveedor:string,monto:decimal,detalle:json,estado:string,creadaEn:timestamp", False, 0
    AddMet clsObligacion, "guardarSiNoExiste", "ObligacionProveedor", "o:ObligacionProveedor", False, 1
    AddMet clsObligacion, "todas", "ObligacionProveedor[]", "", False, 2

    ' ==============================================================
    ' Enums de pagos
    ' ==============================================================
    Set clsMetodo = NuevaClase("MetodoPago", "Enumeration")
    AddLiteral clsMetodo, "qr_bancario", 0
    AddLiteral clsMetodo, "efectivo", 1
    AddLiteral clsMetodo, "beca", 2

    Set clsEstado = NuevaClase("EstadoPago", "Enumeration")
    AddLiteral clsEstado, "pendiente", 0
    AddLiteral clsEstado, "cobrado", 1
    AddLiteral clsEstado, "devuelto", 2
    AddLiteral clsEstado, "fallido", 3

    ' ---------- Relaciones ----------
    ' AddRel origen, destino, nombre, multiplicidad origen, multiplicidad destino
    AddRel clsPago, clsTicket, "genera", "1", "0..1"
    AddRel clsPago, clsMetodo, "se paga con", "*", "1"
    AddRel clsPago, clsEstado, "esta en", "*", "1"
    AddRel clsProveedor, clsObligacion, "tiene", "1", "*"

    ' ---------- Colocar en el diagrama (t y b negativos en EA) ----------
    AddObj clsPago, 20, 470, -20, -470, 1
    AddObj clsMetodo, 20, 190, -560, -690, 2
    AddObj clsEstado, 260, 430, -560, -710, 3
    AddObj clsTicket, 560, 1040, -20, -200, 4
    AddObj clsProveedor, 560, 840, -290, -460, 5
    AddObj clsObligacion, 560, 1120, -550, -800, 6
    oDiagram.DiagramObjects.Refresh

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama de clases 'pagos_tickets' creado (4 clases + 2 enums).", 0

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
