'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE CLASES - Base de Datos menu_inventario (MongoDB)
'
' Cada coleccion es una clase: atributos (-) = campos, metodos (+) = reglas
' de negocio de la clase y metodos del repositorio que guarda/lee la coleccion.
' Porcion y Lote van EMBEBIDOS en menus e insumos: se dibujan con
' composicion (rombo negro).
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

Dim clsPlato
Dim clsMenu
Dim clsPorcion
Dim clsInsumo
Dim clsLote
Dim clsTurno

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Clases ----------
    Set oDiagram = oPackage.Diagrams.AddNew("DC - Base de Datos menu_inventario", "Class")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ==============================================================
    ' Menu   <- coleccion menus
    ' ==============================================================
    Set clsMenu = NuevaClase("Menu", "Class")
    AddAttr clsMenu, "_id", "string", 0
    AddAttr clsMenu, "fecha", "date", 1
    AddAttr clsMenu, "turno", "Turno", 2
    AddAttr clsMenu, "publicado", "bool", 3
    AddAttr clsMenu, "porciones", "Porcion[]", 4
    AddMet clsMenu, "Menu", "", "id:string,fecha:date,turno:Turno", False, 0
    AddMet clsMenu, "reconstituir", "Menu", "id:string,fecha:date,turno:Turno,publicado:bool,porciones:Porcion[]", True, 1
    AddMet clsMenu, "inicioDeSemana", "date", "dia:date", True, 2
    AddMet clsMenu, "agregarPlato", "void", "platoId:string,cupo:int", False, 3
    AddMet clsMenu, "publicar", "void", "", False, 4
    AddMet clsMenu, "apartarPorcion", "void", "platoId:string", False, 5
    AddMet clsMenu, "liberarPorcion", "void", "platoId:string", False, 6
    AddMet clsMenu, "pullEventos", "DomainEvent[]", "", False, 7
    AddMet clsMenu, "save", "Menu", "menu:Menu", False, 8
    AddMet clsMenu, "findById", "Menu", "id:string", False, 9
    AddMet clsMenu, "findBySemana", "Menu[]", "inicioSemana:date,turno:Turno", False, 10
    AddMet clsMenu, "findByRango", "Menu[]", "desde:date,hasta:date", False, 11
    AddMet clsMenu, "findByFechaYTurno", "Menu", "fecha:date,turno:Turno", False, 12

    ' ==============================================================
    ' Porcion   <- porciones[] embebidas en menus
    ' ==============================================================
    Set clsPorcion = NuevaClase("Porcion", "Class")
    AddAttr clsPorcion, "platoId", "string", 0
    AddAttr clsPorcion, "cupoTotal", "int", 1
    AddAttr clsPorcion, "apartadas", "int", 2
    AddMet clsPorcion, "Porcion", "", "platoId:string,cupoTotal:int,apartadas:int", False, 0
    AddMet clsPorcion, "disponibles", "int", "", False, 1
    AddMet clsPorcion, "hayDisponibles", "bool", "", False, 2
    AddMet clsPorcion, "apartarUna", "Porcion", "", False, 3
    AddMet clsPorcion, "liberarUna", "Porcion", "", False, 4
    AddMet clsPorcion, "racionesACocinar", "int", "", False, 5

    ' ==============================================================
    ' Plato   <- coleccion platos (PROPUESTA: hoy no existe)
    ' ==============================================================
    Set clsPlato = NuevaClase("Plato", "Class")
    AddAttr clsPlato, "_id", "string", 0
    AddAttr clsPlato, "nombre", "string", 1
    AddAttr clsPlato, "ingredientes", "array", 2
    AddMet clsPlato, "agregarIngrediente", "void", "insumoId:string,cantidad:float", False, 0
    AddMet clsPlato, "quitarIngrediente", "void", "insumoId:string", False, 1
    AddMet clsPlato, "ingredientes", "Ingrediente[]", "", False, 2

    ' ==============================================================
    ' Insumo   <- coleccion insumos
    ' ==============================================================
    Set clsInsumo = NuevaClase("Insumo", "Class")
    AddAttr clsInsumo, "_id", "string", 0
    AddAttr clsInsumo, "nombre", "string", 1
    AddAttr clsInsumo, "unidad", "string", 2
    AddAttr clsInsumo, "stockMinimo", "float", 3
    AddAttr clsInsumo, "lotes", "Lote[]", 4
    AddMet clsInsumo, "Insumo", "", "id:string,nombre:string,unidad:string,stockMinimo:float", False, 0
    AddMet clsInsumo, "reconstituir", "Insumo", "id:string,nombre:string,unidad:string,stockMinimo:float,lotes:Lote[]", True, 1
    AddMet clsInsumo, "registrarLote", "void", "lote:Lote", False, 2
    AddMet clsInsumo, "stockTotal", "float", "", False, 3
    AddMet clsInsumo, "tieneStockBajo", "bool", "", False, 4
    AddMet clsInsumo, "cantidadSugeridaDeCompra", "int", "", False, 5
    AddMet clsInsumo, "lotesQueVencenHasta", "Lote[]", "limite:date", False, 6
    AddMet clsInsumo, "revisarAlertas", "void", "hoy:date", False, 7
    AddMet clsInsumo, "pullEventos", "DomainEvent[]", "", False, 8
    AddMet clsInsumo, "save", "Insumo", "insumo:Insumo", False, 9
    AddMet clsInsumo, "findById", "Insumo", "id:string", False, 10
    AddMet clsInsumo, "findAll", "Insumo[]", "", False, 11

    ' ==============================================================
    ' Lote   <- lotes[] embebidos en insumos
    ' ==============================================================
    Set clsLote = NuevaClase("Lote", "Class")
    AddAttr clsLote, "loteId", "string", 0
    AddAttr clsLote, "cantidad", "float", 1
    AddAttr clsLote, "fechaVencimiento", "date", 2
    AddMet clsLote, "estaVencida", "bool", "hoy:date", False, 0
    AddMet clsLote, "venceHasta", "bool", "limite:date", False, 1
    AddMet clsLote, "diasRestantes", "int", "hoy:date", False, 2

    ' ==============================================================
    ' Turno   <- enum usado por menus.turno
    ' ==============================================================
    Set clsTurno = NuevaClase("Turno", "Enumeration")
    AddLiteral clsTurno, "DESAYUNO", 0
    AddLiteral clsTurno, "ALMUERZO", 1
    AddLiteral clsTurno, "CENA", 2

    ' ---------- Relaciones ----------
    ' AddComp parte, todo, multiplicidad parte, multiplicidad todo  (rombo negro en el todo)
    AddComp clsPorcion, clsMenu, "*", "1"
    AddComp clsLote, clsInsumo, "*", "1"
    ' AddRel origen, destino, nombre, multiplicidad origen, multiplicidad destino
    AddRel clsPorcion, clsPlato, "es de", "*", "1"
    AddRel clsPlato, clsInsumo, "lleva", "*", "*"
    AddRel clsMenu, clsTurno, "es del", "*", "1"

    ' ---------- Colocar en el diagrama (t y b negativos en EA) ----------
    AddObj clsTurno, 20, 180, -20, -150, 1
    AddObj clsMenu, 20, 560, -220, -620, 2
    AddObj clsPorcion, 20, 440, -720, -930, 3
    AddObj clsPlato, 640, 1000, -720, -880, 4
    AddObj clsInsumo, 640, 1220, -220, -600, 5
    AddObj clsLote, 1120, 1400, -720, -880, 6
    oDiagram.DiagramObjects.Refresh

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama de clases 'menu_inventario' creado (5 clases + enum Turno).", 0

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
' Atributo privado (-) en el orden de la coleccion
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
' Composicion: la parte vive dentro del todo (rombo negro en el todo)
'------------------------------------------------------------------
Sub AddComp(oParte, oTodo, sMultParte, sMultTodo)
    Dim con
    Set con = oParte.Connectors.AddNew("", "Aggregation")
    con.Subtype = "Strong"
    con.SupplierID = oTodo.ElementID
    con.ClientEnd.Cardinality = sMultParte
    con.SupplierEnd.Cardinality = sMultTodo
    con.SupplierEnd.Aggregation = 2
    con.Update
    oParte.Connectors.Refresh
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
