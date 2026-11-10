'==================================================================
' Script de Enterprise Architect (VBScript)
' INSPECTOR - muestra como guardo EA los conectores del diagrama abierto
'
' Sirve para copiar EXACTAMENTE lo que EA guarda cuando haces a mano
' "Add Message from A to B" sobre una asociacion.
'
' USO:
' 1. Abri el diagrama donde hiciste el mensaje a mano (el de "sdasd()")
' 2. Corre este script
' 3. Copia todo lo que sale en la ventana System Output -> pestana Script
'==================================================================

option explicit

!INC Local Scripts.EAConstants-VBScript

Sub Main
    Dim dg, i, j, el, con, vistos, m, linea

    Set dg = Repository.GetCurrentDiagram()
    If dg Is Nothing Then
        Session.Prompt "Abri primero el diagrama que queres inspeccionar.", 0
        Exit Sub
    End If

    Repository.EnsureOutputVisible "Script"
    Session.Output "=== Diagrama: " & dg.Name & " | Type=" & dg.Type & " | DiagramID=" & dg.DiagramID
    Session.Output "    StyleEx=" & dg.StyleEx
    Session.Output "    ExtendedStyle=" & dg.ExtendedStyle

    Set vistos = CreateObject("Scripting.Dictionary")

    For i = 0 To dg.DiagramObjects.Count - 1
        Set el = Repository.GetElementByID(dg.DiagramObjects.GetAt(i).ElementID)
        Session.Output "--- Elemento: " & el.Name & " | Type=" & el.Type & " | Stereotype=" & el.Stereotype & " | ElementID=" & el.ElementID
        For j = 0 To el.Connectors.Count - 1
            Set con = el.Connectors.GetAt(j)
            If Not vistos.Exists(con.ConnectorID) Then
                vistos.Add con.ConnectorID, True
                linea = "  ConnectorID=" & con.ConnectorID & " | Type=" & con.Type & " | Subtype=" & con.Subtype & _
                        " | Name=" & con.Name & " | ClientID=" & con.ClientID & " | SupplierID=" & con.SupplierID & _
                        " | DiagramID=" & con.DiagramID & " | SequenceNo=" & con.SequenceNo & _
                        " | Direction=" & con.Direction & " | Stereotype=" & con.Stereotype
                Session.Output linea
                Session.Output "      StyleEx=" & con.StyleEx
                Session.Output "      StateFlags=" & con.StateFlags & " | EventFlags=" & con.EventFlags
                Session.Output "      TransitionEvent=" & con.TransitionEvent & " | TransitionGuard=" & con.TransitionGuard & " | TransitionAction=" & con.TransitionAction
                On Error Resume Next
                For m = 0 To 4
                    Session.Output "      MiscData(" & m & ")=" & con.MiscData(m)
                Next
                On Error GoTo 0
            End If
        Next
    Next

    Session.Output "=== DiagramLinks"
    For i = 0 To dg.DiagramLinks.Count - 1
        Session.Output "  ConnectorID=" & dg.DiagramLinks.GetAt(i).ConnectorID & " | Style=" & dg.DiagramLinks.GetAt(i).Style & " | Geometry=" & dg.DiagramLinks.GetAt(i).Geometry
    Next

    ' Filas crudas de la base: muestran TODOS los campos, tambien los que la API no expone
    Session.Output "=== SQL t_connector (mensajes Collaboration de este diagrama)"
    Session.Output Repository.SQLQuery("SELECT * FROM t_connector WHERE Connector_Type='Collaboration' AND " & _
        "(DiagramID=" & dg.DiagramID & " OR Start_Object_ID IN (SELECT Object_ID FROM t_diagramobjects WHERE Diagram_ID=" & dg.DiagramID & "))")

    Session.Output "=== SQL t_diagramlinks (de este diagrama)"
    Session.Output Repository.SQLQuery("SELECT * FROM t_diagramlinks WHERE DiagramID=" & dg.DiagramID)

    Session.Output "=== Fin"
End Sub

Main
