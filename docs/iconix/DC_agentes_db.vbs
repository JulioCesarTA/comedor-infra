'==================================================================
' Script de Enterprise Architect (VBScript)
' DIAGRAMA DE CLASES - Base de Datos agentes.db (SQLite, ia-ml-service)
'
' Cada tabla es una clase: atributos (-) = columnas, metodos (+) = funciones
' del repositorio de esa tabla (app/application/ports/repositorios.py).
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

Dim clsPropuesta
Dim clsMensaje
Dim clsConfig
Dim clsChat
Dim clsPagoTg
Dim clsRefPorcion
Dim clsDispositivo
Dim clsBandeja

Sub Main

    Set oPackage = Repository.GetTreeSelectedPackage()
    If oPackage Is Nothing Then
        Session.Prompt "Selecciona primero un paquete en el Browser.", 0
        Exit Sub
    End If

    ' ---------- Crear el diagrama de Clases ----------
    Set oDiagram = oPackage.Diagrams.AddNew("DC - Base de Datos agentes.db", "Class")
    oDiagram.Update
    oPackage.Diagrams.Refresh

    ' ==============================================================
    ' Propuesta   <- tabla propuestas
    ' ==============================================================
    Set clsPropuesta = NuevaClase("Propuesta", "Class")
    AddAttr clsPropuesta, "id", "string", 0
    AddAttr clsPropuesta, "tipo", "string", 1
    AddAttr clsPropuesta, "clave", "string", 2
    AddAttr clsPropuesta, "titulo", "string", 3
    AddAttr clsPropuesta, "resumen", "string", 4
    AddAttr clsPropuesta, "payload", "json", 5
    AddAttr clsPropuesta, "estado", "string", 6
    AddAttr clsPropuesta, "creado", "timestamp", 7
    AddAttr clsPropuesta, "resuelto", "timestamp", 8
    AddAttr clsPropuesta, "resultado", "string", 9
    AddMet clsPropuesta, "obtener", "Propuesta", "pid:string", False, 0
    AddMet clsPropuesta, "listar", "Propuesta[]", "estado:string,limite:int", False, 1
    AddMet clsPropuesta, "crear_si_no_hay_vigente", "tuple[Propuesta; bool]", "tipo:string,clave:string,titulo:string,resumen:string,payload:json,forzar:bool,informativa:bool,ventana_s:float", False, 2
    AddMet clsPropuesta, "tomar_pendiente", "bool", "pid:string,nuevo_estado:string,resultado:string", False, 3
    AddMet clsPropuesta, "cerrar", "void", "pid:string,estado:string,resultado:string", False, 4

    ' ==============================================================
    ' Mensaje   <- tabla outbox
    ' ==============================================================
    Set clsMensaje = NuevaClase("Mensaje", "Class")
    AddAttr clsMensaje, "id", "int", 0
    AddAttr clsMensaje, "texto", "string", 1
    AddAttr clsMensaje, "propuesta_id", "string", 2
    AddAttr clsMensaje, "con_botones", "bool", 3
    AddAttr clsMensaje, "creado", "timestamp", 4
    AddAttr clsMensaje, "intentos", "int", 5
    AddAttr clsMensaje, "chat_id", "string", 6
    AddMet clsMensaje, "encolar", "void", "texto:string,propuesta_id:string,chat_id:string,con_botones:bool,creado:timestamp", False, 0
    AddMet clsMensaje, "mensajes_en_cola", "int", "", False, 1
    AddMet clsMensaje, "cola", "Mensaje[]", "", False, 2
    AddMet clsMensaje, "repartir", "void", "mensaje:Mensaje,destinos:string[]", False, 3
    AddMet clsMensaje, "sumar_intento", "void", "mensaje_id:int", False, 4
    AddMet clsMensaje, "quitar_de_cola", "void", "mensaje_id:int", False, 5

    ' ==============================================================
    ' Chat   <- tabla chats
    ' ==============================================================
    Set clsChat = NuevaClase("Chat", "Class")
    AddAttr clsChat, "chat_id", "string", 0
    AddAttr clsChat, "estado", "string", 1
    AddAttr clsChat, "email", "string", 2
    AddAttr clsChat, "username", "string", 3
    AddAttr clsChat, "nombre", "string", 4
    AddAttr clsChat, "roles", "json", 5
    AddAttr clsChat, "intentos", "int", 6
    AddAttr clsChat, "ctx", "json", 7
    AddAttr clsChat, "actualizado", "timestamp", 8
    AddMet clsChat, "chat", "Chat", "cid:string", False, 0
    AddMet clsChat, "guardar_chat", "Chat", "cid:string,campos:dict", False, 1
    AddMet clsChat, "borrar_chat", "void", "cid:string", False, 2
    AddMet clsChat, "chats_listos", "Chat[]", "", False, 3

    ' ==============================================================
    ' PagoTelegram   <- tabla pagos_tg
    ' ==============================================================
    Set clsPagoTg = NuevaClase("PagoTelegram", "Class")
    AddAttr clsPagoTg, "reserva_id", "uuid", 0
    AddAttr clsPagoTg, "chat_id", "string", 1
    AddAttr clsPagoTg, "referencia", "string", 2
    AddAttr clsPagoTg, "estado", "string", 3
    AddAttr clsPagoTg, "intentos", "int", 4
    AddAttr clsPagoTg, "creado", "timestamp", 5
    AddMet clsPagoTg, "guardar_pago", "void", "reserva_id:string,chat_id:string,referencia:string,plato:string,fecha:string,turno:string", False, 0
    AddMet clsPagoTg, "pago", "PagoTelegram", "reserva_id:string", False, 1
    AddMet clsPagoTg, "marcar_pago", "void", "reserva_id:string,estado:string,intentos:int", False, 2
    AddMet clsPagoTg, "pagos_en_curso", "PagoTelegram[]", "", False, 3

    ' ==============================================================
    ' Config   <- tabla config
    ' ==============================================================
    Set clsConfig = NuevaClase("Config", "Class")
    AddAttr clsConfig, "k", "string", 0
    AddAttr clsConfig, "v", "string", 1
    AddMet clsConfig, "leer", "string", "k:string", False, 0
    AddMet clsConfig, "escribir", "string", "k:string,v:string", False, 1

    ' ==============================================================
    ' ReferenciaPorcion   <- tabla ref_porcion
    ' ==============================================================
    Set clsRefPorcion = NuevaClase("ReferenciaPorcion", "Class")
    AddAttr clsRefPorcion, "id", "string", 0
    AddAttr clsRefPorcion, "plato_id", "string", 1
    AddAttr clsRefPorcion, "fecha", "date", 2
    AddAttr clsRefPorcion, "turno", "string", 3
    AddAttr clsRefPorcion, "creado", "timestamp", 4
    AddAttr clsRefPorcion, "f_ref", "float", 5
    AddAttr clsRefPorcion, "advertencia", "string", 6
    AddAttr clsRefPorcion, "foto_key", "string", 7
    AddAttr clsRefPorcion, "origen", "string", 8
    AddAttr clsRefPorcion, "cliente_id", "string", 9
    AddMet clsRefPorcion, "guardar_referencia", "void", "rid:string,plato_id:string,fecha:string,turno:string,f_ref:float,advertencia:string,foto_key:string,origen:string,cliente_id:string", False, 0
    AddMet clsRefPorcion, "referencia", "ReferenciaPorcion", "ref_id:string", False, 1
    AddMet clsRefPorcion, "referencias", "ReferenciaPorcion[]", "limite:int", False, 2
    AddMet clsRefPorcion, "por_cliente", "dict", "tabla:string,cliente_id:string", False, 3
    AddMet clsRefPorcion, "foto_key", "string", "carpeta:string,fid:string", False, 4

    ' ==============================================================
    ' Bandeja   <- tabla bandejas
    ' ==============================================================
    Set clsBandeja = NuevaClase("Bandeja", "Class")
    AddAttr clsBandeja, "id", "string", 0
    AddAttr clsBandeja, "ref_id", "string", 1
    AddAttr clsBandeja, "plato_id", "string", 2
    AddAttr clsBandeja, "fecha", "date", 3
    AddAttr clsBandeja, "turno", "string", 4
    AddAttr clsBandeja, "creado", "timestamp", 5
    AddAttr clsBandeja, "restante", "float", 6
    AddAttr clsBandeja, "comido", "float", 7
    AddAttr clsBandeja, "confianza", "float", 8
    AddAttr clsBandeja, "foto_key", "string", 9
    AddAttr clsBandeja, "origen", "string", 10
    AddAttr clsBandeja, "cliente_id", "string", 11
    AddMet clsBandeja, "guardar_bandeja", "void", "bid:string,ref_id:string,plato_id:string,fecha:string,turno:string,restante:float,comido:float,confianza:float,foto_key:string,origen:string,cliente_id:string", False, 0
    AddMet clsBandeja, "resumen_bandejas", "dict", "", False, 1
    AddMet clsBandeja, "restante_medio_por_plato", "dict", "minimo_bandejas:int", False, 2
    AddMet clsBandeja, "todas_las_bandejas", "Bandeja[]", "", False, 3
    AddMet clsBandeja, "por_cliente", "dict", "tabla:string,cliente_id:string", False, 4

    ' ==============================================================
    ' Dispositivo   <- tabla dispositivos
    ' ==============================================================
    Set clsDispositivo = NuevaClase("Dispositivo", "Class")
    AddAttr clsDispositivo, "token", "string", 0
    AddAttr clsDispositivo, "usuario", "string", 1
    AddAttr clsDispositivo, "roles", "json", 2
    AddAttr clsDispositivo, "plataforma", "string", 3
    AddAttr clsDispositivo, "actualizado", "timestamp", 4
    AddMet clsDispositivo, "registrar", "void", "token:string,usuario:string,roles:string[],plataforma:string", False, 0
    AddMet clsDispositivo, "dar_de_baja", "bool", "token:string", False, 1
    AddMet clsDispositivo, "de_usuario", "Dispositivo[]", "usuario:string", False, 2
    AddMet clsDispositivo, "de_roles", "Dispositivo[]", "roles:string[]", False, 3
    AddMet clsDispositivo, "contar", "int", "", False, 4

    ' ---------- Relaciones ----------
    ' AddRel origen, destino, nombre, multiplicidad origen, multiplicidad destino
    AddRel clsPropuesta, clsMensaje, "se avisa en", "0..1", "*"
    AddRel clsChat, clsMensaje, "recibe", "0..1", "*"
    AddRel clsChat, clsPagoTg, "espera", "1", "*"
    AddRel clsRefPorcion, clsBandeja, "sirve de base a", "1", "*"

    ' ---------- Colocar en el diagrama (t y b negativos en EA) ----------
    ' Fila 1: Propuesta - Mensaje - Chat - PagoTelegram
    AddObj clsPropuesta, 20, 700, -20, -360, 1
    AddObj clsMensaje, 780, 1380, -20, -320, 2
    AddObj clsChat, 1460, 1800, -20, -330, 3
    AddObj clsPagoTg, 1460, 2120, -420, -640, 4
    ' Fila 2: ReferenciaPorcion - Bandeja - Dispositivo - Config
    AddObj clsRefPorcion, 20, 820, -460, -800, 5
    AddObj clsBandeja, 20, 940, -880, -1240, 6
    AddObj clsDispositivo, 1040, 1520, -720, -940, 7
    AddObj clsConfig, 1040, 1340, -1020, -1140, 8
    oDiagram.DiagramObjects.Refresh

    Repository.ReloadDiagram oDiagram.DiagramID
    Repository.OpenDiagram oDiagram.DiagramID

    Session.Prompt "Diagrama de clases 'agentes.db' creado (8 tablas).", 0

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
