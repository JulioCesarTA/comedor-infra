'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE CLASES - Base de Datos DynamoDB (sagas, ia-ml-service)
'
' Cada tabla es una clase: atributos (-) = campos, metodos (+) = funciones
' del almacen de sagas (app/application/ports/sagas.py).
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

Dim clsClave
Dim clsSaga

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Clases ----------
    Set oDiagram = oPackage.Diagrams.AddNew("DC - Base de Datos DynamoDB", "Class")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ==============================================================
    ' ClaveIdempotencia   <- tabla idempotency_keys
    ' ==============================================================
    Set clsClave = NuevaClase("ClaveIdempotencia", "Class")
    AddAttr clsClave, "idempotencyKey", "string", 0
    AddAttr clsClave, "sagaId", "string", 1
    AddAttr clsClave, "cachedResponse", "json", 2
    AddMet clsClave, "asegurar_tablas", "void", "", False, 0
    AddMet clsClave, "bloquear_idempotencia", "dict", "clave:string,respuesta:dict", False, 1
    AddMet clsClave, "guardar_respuesta_idempotencia", "void", "clave:string,respuesta:dict", False, 2

    ' ==============================================================
    ' Saga   <- tabla sagas
    ' ==============================================================
    Set clsSaga = NuevaClase("Saga", "Class")
    AddAttr clsSaga, "sagaId", "string", 0
    AddAttr clsSaga, "data", "json", 1
    AddMet clsSaga, "guardar_saga", "void", "saga_id:string,datos:dict", False, 0
    AddMet clsSaga, "obtener_saga", "dict", "saga_id:string", False, 1

    ' ---------- Relaciones ----------
    ' AddRel origen, destino, nombre, multiplicidad origen, multiplicidad destino
    AddRel clsClave, clsSaga, "protege", "*", "0..1"

    ' ---------- Colocar en el diagrama (t y b negativos en EA) ----------
    AddObj clsClave, 20, 480, -20, -200, 1
    AddObj clsSaga, 640, 960, -20, -170, 2
    oDiagram.DiagramObjects.Refresh

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama de clases 'DynamoDB' creado (2 tablas).", 0

End Sub

'------------------------------------------------------------------
' Crea una clase en el paquete
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
