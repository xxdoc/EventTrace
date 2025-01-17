Attribute VB_Name = "modFastFuncs"
Option Explicit

Private Declare Function SysAllocStringByteLen Lib "oleaut32" (ByVal olestr As Long, ByVal BLen As Long) As Long
Private Declare Function ArrPtr& Lib "msvbvm60.dll" Alias "VarPtr" (ptr() As Any)
Private Declare Sub RtlMoveMemory Lib "kernel32" (dst As Any, src As Any, ByVal nBytes&)
Private Declare Sub RtlZeroMemory Lib "kernel32" (dst As Any, ByVal nBytes&)
Private Type SafeArray1D
  cDims       As Integer
  fFeatures   As Integer
  cbElements  As Long
  cLocks      As Long
  pvData      As Long
  cElements   As Long
  lLBound     As Long
End Type

Private Const FADF_AUTO As Long = &H1        '// Array is allocated on the stack.
Private Const FADF_FIXEDSIZE As Long = &H10  '// Array may not be resized or reallocated.

Public Function Replace08(ByRef Text As String, _
    ByRef sOld As String, ByRef sNew As String, _
    Optional ByVal start As Long = 1, _
    Optional ByVal Count As Long = 2147483647, _
    Optional ByVal Compare As VbCompareMethod = vbBinaryCompare _
  ) As String
' by Jost Schwider, jost@schwider.de, 20001218

  If LenB(sOld) Then

    If Compare = vbBinaryCompare Then
      Replace08Bin Replace08, Text, Text, _
          sOld, sNew, start, Count
    Else
      Replace08Bin Replace08, Text, LCase$(Text), _
          LCase$(sOld), sNew, start, Count
    End If

  Else 'Suchstring ist leer:
    Replace08 = Text
  End If
End Function

Private Static Sub Replace08Bin(ByRef result As String, _
    ByRef Text As String, ByRef Search As String, _
    ByRef sOld As String, ByRef sNew As String, _
    ByVal start As Long, ByVal Count As Long _
  )
' by Jost Schwider, jost@schwider.de, 20001218
  Dim TextLen As Long
  Dim OldLen As Long
  Dim NewLen As Long
  Dim ReadPos As Long
  Dim WritePos As Long
  Dim CopyLen As Long
  Dim Buffer As String
  Dim BufferLen As Long
  Dim BufferPosNew As Long
  Dim BufferPosNext As Long

  'Ersten Treffer bestimmen:
  If start < 2 Then
    start = InStrB(Search, sOld)
  Else
    start = InStrB(start + start - 1, Search, sOld)
  End If
  If start Then

    OldLen = LenB(sOld)
    NewLen = LenB(sNew)
    Select Case NewLen
    Case OldLen 'einfaches �berschreiben:

      result = Text
      For Count = 1 To Count
        MidB$(result, start) = sNew
        start = InStrB(start + OldLen, Search, sOld)
        If start = 0 Then Exit Sub
      Next Count

    Case 0 'nur Entfernen:

      'Buffer initialisieren:
      TextLen = LenB(Text)
      If TextLen > BufferLen Then
        Buffer = Text
        BufferLen = TextLen
      End If

      'Ausschneiden:
      ReadPos = 1
      WritePos = 1
      For Count = 1 To Count
        CopyLen = start - ReadPos
        If CopyLen Then
          MidB$(Buffer, WritePos) = MidB$(Text, ReadPos, CopyLen)
          WritePos = WritePos + CopyLen
        End If
        ReadPos = start + OldLen
        start = InStrB(ReadPos, Search, sOld)
        If start = 0 Then Exit For
      Next Count

      'Ergebnis zusammenbauen:
      If ReadPos > TextLen Then
        result = LeftB$(Buffer, WritePos - 1)
      Else
        MidB$(Buffer, WritePos) = MidB$(Text, ReadPos)
        result = LeftB$(Buffer, WritePos + TextLen - ReadPos)
      End If
      Exit Sub

    Case Is < OldLen 'Ergebnis wird k�rzer:

      'Buffer initialisieren:
      TextLen = LenB(Text)
      If TextLen > BufferLen Then
        Buffer = Text
        BufferLen = TextLen
      End If

      'Ersetzen:
      ReadPos = 1
      WritePos = 1
      For Count = 1 To Count
        CopyLen = start - ReadPos
        If CopyLen Then
          BufferPosNew = WritePos + CopyLen
          MidB$(Buffer, WritePos) = MidB$(Text, ReadPos, CopyLen)
          MidB$(Buffer, BufferPosNew) = sNew
          WritePos = BufferPosNew + NewLen
        Else
          MidB$(Buffer, WritePos) = sNew
          WritePos = WritePos + NewLen
        End If
        ReadPos = start + OldLen
        start = InStrB(ReadPos, Search, sOld)
        If start = 0 Then Exit For
      Next Count

      'Ergebnis zusammenbauen:
      If ReadPos > TextLen Then
        result = LeftB$(Buffer, WritePos - 1)
      Else
        MidB$(Buffer, WritePos) = MidB$(Text, ReadPos)
        result = LeftB$(Buffer, WritePos + LenB(Text) - ReadPos)
      End If
      Exit Sub

    Case Else 'Ergebnis wird l�nger:

      'Buffer initialisieren:
      TextLen = LenB(Text)
      BufferPosNew = TextLen + NewLen
      If BufferPosNew > BufferLen Then
        Buffer = Space$(BufferPosNew)
        BufferLen = LenB(Buffer)
      End If

      'Ersetzung:
      ReadPos = 1
      WritePos = 1
      For Count = 1 To Count
        CopyLen = start - ReadPos
        If CopyLen Then
          'Positionen berechnen:
          BufferPosNew = WritePos + CopyLen
          BufferPosNext = BufferPosNew + NewLen

          'Ggf. Buffer vergr��ern:
          If BufferPosNext > BufferLen Then
            Buffer = Buffer & Space$(BufferPosNext)
            BufferLen = LenB(Buffer)
          End If

          'String "patchen":
          MidB$(Buffer, WritePos) = MidB$(Text, ReadPos, CopyLen)
          MidB$(Buffer, BufferPosNew) = sNew
          WritePos = BufferPosNext
        Else
          'Position bestimmen:
          BufferPosNext = WritePos + NewLen

          'Ggf. Buffer vergr��ern:
          If BufferPosNext > BufferLen Then
            Buffer = Buffer & Space$(BufferPosNext)
            BufferLen = LenB(Buffer)
          End If

          'String "patchen":
          MidB$(Buffer, WritePos) = sNew
          WritePos = BufferPosNext
        End If
        ReadPos = start + OldLen
        start = InStrB(ReadPos, Search, sOld)
        If start = 0 Then Exit For
      Next Count

      'Ergebnis zusammenbauen:
      If ReadPos > TextLen Then
        result = LeftB$(Buffer, WritePos - 1)
      Else
        BufferPosNext = WritePos + TextLen - ReadPos
        If BufferPosNext < BufferLen Then
          MidB$(Buffer, WritePos) = MidB$(Text, ReadPos)
          result = LeftB$(Buffer, BufferPosNext)
        Else
          result = LeftB$(Buffer, WritePos - 1) & MidB$(Text, ReadPos)
        End If
      End If
      Exit Sub

    End Select

  Else 'Kein Treffer:
    result = Text
  End If
End Sub

Public Function LCase02(ByRef sString As String) As String
' by Donald, donald@xbeat.net, 20011209
    Static saDst As SafeArray1D
    Static aDst%()
    Static pDst&, psaDst&
    Static init As Long
    Dim c As Long
    Dim lLen As Long
    Static iLUT(0 To 400) As Integer

    If init Then
    Else
        saDst.cDims = 1
        saDst.cbElements = 2
        saDst.cElements = &H7FFFFFFF

        pDst = VarPtr(saDst)
        psaDst = ArrPtr(aDst)

        ' init LUT
        For c = 0 To 255: iLUT(c) = AscW(LCase$(Chr$(c))): Next
        For c = 256 To 400: iLUT(c) = c: Next
        iLUT(352) = 353
        iLUT(338) = 339
        iLUT(381) = 382
        iLUT(376) = 255

        init = 1
    End If

    lLen = Len(sString)
    RtlMoveMemory ByVal VarPtr(LCase02), _
        SysAllocStringByteLen(StrPtr(sString), lLen + lLen), 4
    saDst.pvData = StrPtr(LCase02)
    RtlMoveMemory ByVal psaDst, pDst, 4

    For c = 0 To lLen - 1
      Select Case aDst(c)
      Case 65 To 381
        aDst(c) = iLUT(aDst(c))
      End Select
    Next

    RtlMoveMemory ByVal psaDst, 0&, 4

End Function

