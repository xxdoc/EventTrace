Attribute VB_Name = "modFileDialog"
' *********************************************************************
'  Copyright �2007-10 Karl E. Peterson, All Rights Reserved
'  http://vb.mvps.org/
' *********************************************************************
'  Based on the work of Bruce McKinney, in "Hardcore Visual Basic"
'  http://vb.mvps.org/hardcore
' *********************************************************************
'  You are free to use this code within your own applications, but you
'  are expressly forbidden from selling or otherwise distributing this
'  source code without prior written consent.
' *********************************************************************
Option Explicit

' Win32 API declarations
Private Declare Function GetVersionEx Lib "kernel32" Alias "GetVersionExA" (lpVersionInformation As Any) As Long
Private Declare Function SetWindowLong Lib "user32" Alias "SetWindowLongW" (ByVal hWnd As Long, ByVal nIndex As Long, ByVal dwNewLong As Long) As Long
Private Declare Function PathCombineW Lib "shlwapi" (ByVal lpszDest As Long, ByVal lpszDir As Long, ByVal lpszFile As Long) As Boolean
Private Declare Function PathFileExistsW Lib "shlwapi" (ByVal lpszPath As Long) As Boolean
Private Declare Function PathIsDirectoryW Lib "shlwapi" (ByVal lpszPath As Long) As Boolean
Private Declare Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (Destination As Any, Source As Any, ByVal Length As Long)
Private Declare Function lstrlenA Lib "kernel32" (ByVal lpString As Long) As Long
Private Declare Function lstrlenW Lib "kernel32" (ByVal lpString As Long) As Long

Private Type OSVERSIONINFO
   dwOSVersionInfoSize As Long
   dwMajorVersion As Long
   dwMinorVersion As Long
   dwBuildNumber As Long
   dwPlatformId As Long
   szCSDVersion As String * 128
End Type

Private Const DWL_MSGRESULT As Long = 0

' =====================================================================
'  Definitions used with the File dialogs
' =====================================================================
Private Declare Function GetOpenFileName Lib "COMDLG32" Alias "GetOpenFileNameW" (pOpenFile As OpenFileNameType) As Long
Private Declare Function GetSaveFileName Lib "COMDLG32" Alias "GetSaveFileNameW" (pOpenFile As OpenFileNameType) As Long
Private Declare Function GetParent Lib "user32" (ByVal hWnd As Long) As Long
Private Declare Function SendMessage Lib "user32" Alias "SendMessageW" (ByVal hWnd As Long, ByVal wMsg As Long, ByVal wParam As Long, lParam As Any) As Long
Private Declare Function CommDlgExtendedError Lib "comdlg32.dll" () As Long

Private Type OpenFileNameType
   lStructSize As Long          ' Filled with UDT size
   hwndOwner As Long            ' Tied to Owner
   hInstance As Long            ' Ignored (used only by templates)
   lpstrFilter As Long          ' Tied to Filter
   lpstrCustomFilter As Long    ' Ignored (exercise for reader)
   nMaxCustFilter As Long       ' Ignored (exercise for reader)
   nFilterIndex As Long         ' Tied to FilterIndex
   lpstrFile As Long            ' Tied to FileName
   nMaxFile As Long             ' Handled internally
   lpstrFileTitle As Long       ' Tied to FileTitle
   nMaxFileTitle As Long        ' Handled internally
   lpstrInitialDir As Long      ' Tied to InitDir
   lpstrTitle As Long           ' Tied to DlgTitle
   Flags As Long                ' Tied to Flags
   nFileOffset As Integer       ' Ignored (exercise for reader)
   nFileExtension As Integer    ' Ignored (exercise for reader)
   lpstrDefExt As Long          ' Tied to DefaultExt
   lCustData As Long            ' Ignored (needed for hooks)
   lpfnHook As Long             ' Ignored (good luck with hooks)
   lpTemplateName As Long       ' Ignored (good luck with templates)
   ' #if (WINVER >= 0x0500)
   pvReserved As Long           ' Reserved. Must be set to NULL.
   dwReserved As Long           ' Reserved. Must be set to 0.
   FlagsEx As Long              ' Initialize the dialog in 2000/XP.
End Type

Private Const OPENFILENAME_SIZE_VERSION_400 As Long = 76  ' Pre W2K size
Private Const FNERR_BUFFERTOOSMALL As Long = &H3003

Private Type tagNMHDR
    hWndFrom As Long
    idFrom As Long
    code As Long
End Type

Private Type OFNOTIFY
   hdr As tagNMHDR
   lpOFN As Long
   pszFile As Long
End Type

Public Enum OpenFileFlags
   OFN_READONLY = &H1
   OFN_OVERWRITEPROMPT = &H2
   OFN_HIDEREADONLY = &H4
   OFN_NOCHANGEDIR = &H8
   OFN_SHOWHELP = &H10
   OFN_ENABLEHOOK = &H20
   OFN_ENABLETEMPLATE = &H40
   OFN_ENABLETEMPLATEHANDLE = &H80
   OFN_NOVALIDATE = &H100
   OFN_ALLOWMULTISELECT = &H200
   OFN_EXTENSIONDIFFERENT = &H400
   OFN_PATHMUSTEXIST = &H800
   OFN_FILEMUSTEXIST = &H1000
   OFN_CREATEPROMPT = &H2000
   OFN_SHAREAWARE = &H4000
   OFN_NOREADONLYRETURN = &H8000
   OFN_NOTESTFILECREATE = &H10000
   OFN_NONETWORKBUTTON = &H20000
   OFN_NOLONGNAMES = &H40000
   ' #if (WINVER >= 0x0400)
   OFN_EXPLORER = &H80000
   OFN_NODEREFERENCELINKS = &H100000
   OFN_LONGNAMES = &H200000
   OFN_ENABLEINCLUDENOTIFY = &H400000
   OFN_ENABLESIZING = &H800000
   ' #if (WINVER >= 0x0500)
   OFN_DONTADDTORECENT = &H2000000
   OFN_FORCESHOWHIDDEN = &H10000000
End Enum

Public Enum OpenFileFlagsEx
   OFN_EX_NOPLACESBAR = &H1
End Enum

Private Const CDN_FIRST As Long = -601
Private Const CDN_LAST As Long = -699
Private Const CDN_INITDONE As Long = (CDN_FIRST - &H0)
Private Const CDN_SELCHANGE As Long = (CDN_FIRST - &H1)
Private Const CDN_FOLDERCHANGE As Long = (CDN_FIRST - &H2)
Private Const CDN_SHAREVIOLATION As Long = (CDN_FIRST - &H3)
Private Const CDN_HELP As Long = (CDN_FIRST - &H4)
Private Const CDN_FILEOK As Long = (CDN_FIRST - &H5)
Private Const CDN_TYPECHANGE As Long = (CDN_FIRST - &H6)
Private Const CDN_INCLUDEITEM As Long = (CDN_FIRST - &H7)

Private Const WM_NOTIFY As Long = &H4E
Private Const WM_INITDIALOG As Long = &H110
Private Const WM_USER As Long = &H400

Private Const CDM_FIRST As Long = (WM_USER + 100)
Private Const CDM_LAST As Long = (WM_USER + 200)
Private Const CDM_GETSPEC As Long = (CDM_FIRST + &H0)
Private Const CDM_GETFILEPATH As Long = (CDM_FIRST + &H1)
Private Const CDM_GETFOLDERPATH As Long = (CDM_FIRST + &H2)
Private Const CDM_GETFOLDERIDLIST As Long = (CDM_FIRST + &H3)
Private Const CDM_SETCONTROLTEXT As Long = (CDM_FIRST + &H4)
Private Const CDM_HIDECONTROL As Long = (CDM_FIRST + &H5)
Private Const CDM_SETDEFEXT As Long = (CDM_FIRST + &H6)

' Dependencies Bruce didn't include...
Private Const MAX_PATH As Long = 260
Private Const MAX_FILE As Long = 260
Private Const sEmpty As String = ""

' Overflow buffers.
Private m_FileEx As String      ' Buffer for selected files
Private m_FolderEx As String    ' Buffer for selected folder
Private m_MustExist As Boolean  ' Windows 7 forces manual flag!

' =====================================================================
'  Public Methods
' =====================================================================
Public Function FileExists(ByVal FileName As String) As Boolean
   ' Combines a few functions, to test if path points to existing file.
   If PathIsDirectoryW(StrPtr(FileName)) = False Then
      If PathFileExistsW(StrPtr(FileName)) Then
         FileExists = True
      End If
   End If
End Function

Public Function FolderExists(ByVal PathName As String) As Boolean
   ' Verifies that a path is a valid directory.
   FolderExists = PathIsDirectoryW(StrPtr(PathName))
End Function

Public Function GetOpenName(FileName As String, Optional FileMustExist As Boolean = True, Optional MultiSelect As Boolean = False, Optional ReadOnly As Boolean = False, Optional HideReadOnly As Boolean = False, Optional Filter As String = "All (*.*)| *.*", Optional FilterIndex As Long = 1, Optional InitDir As String, Optional DlgTitle As String, Optional DefaultExt As String, Optional Owner As Long = 0, Optional Flags As Long = 0) As Long
   Dim WinVer As Long, os As OSVERSIONINFO
   Dim opfile As OpenFileNameType
   Dim TheFiles() As String
   Dim Success As Boolean
   Dim i As Integer
   
   ' Determine Windows version info.
   os.dwOSVersionInfoSize = Len(os)
   Call GetVersionEx(os)
   WinVer = os.dwMajorVersion * 100 + os.dwMinorVersion
   
   With opfile
      ' Additional fields supported in Windows 2000+
'      If WinVer >= 500 Then
         .lStructSize = Len(opfile)
'      Else
'         .lStructSize = OPENFILENAME_SIZE_VERSION_400
'      End If
      
      ' Add in specific flags and strip out non-VB flags
      .Flags = (-MultiSelect * OFN_ALLOWMULTISELECT) Or _
               (-ReadOnly * OFN_READONLY) Or _
               (-HideReadOnly * OFN_HIDEREADONLY) Or _
               (Flags And CLng(Not (OFN_ENABLEHOOK Or _
                                    OFN_ENABLETEMPLATE)))
                                    
      ' Windows 7 preempts the CDN_FILEOK notification if this
      ' flag is set and the file does't exist, which prevents us
      ' from displaying a custom error dialog.  :-(
      m_MustExist = FileMustExist

      ' Always use the Explorer style interface.
      .Flags = .Flags Or OFN_EXPLORER Or OFN_ENABLESIZING
      
      ' Using the Unicode APIs means that buffer overflow is
      ' always possible, so force the callback.
      ' With ANSI, only do so as needed.
      'If MultiSelect Or FileMustExist Then
         .Flags = .Flags Or OFN_ENABLEHOOK
         .lpfnHook = FncPtr(AddressOf OFNHookProc)
      'End If
      
      ' Places bar doesn't show if OFN_ENABLEHOOK is set *and* the
      ' structure is only OPENFILENAME_SIZE_VERSION_400 long!
      ' Places also bar doesn't show if OFN_EX_NOPLACESBAR is set.
      If WinVer >= 500 Then
         ' .FlagsEx = OFN_EX_NOPLACESBAR
      End If
      
      ' Owner can take handle of owning window
      If Owner Then .hwndOwner = Owner
      ' InitDir can take initial directory string
      .lpstrInitialDir = StrPtr(InitDir)
      ' DefaultExt can take default extension
      .lpstrDefExt = StrPtr(DefaultExt)
      ' DlgTitle can take dialog box title
      .lpstrTitle = StrPtr(DlgTitle)
      
      ' To make Windows-style filter, replace | and : with nulls.
      ' Put double null at end.
      Filter = Filter & vbNullChar & vbNullChar
      For i = 1 To Len(Filter)
         Select Case Mid$(Filter, i, 1)
            Case "|", ":"
               Mid$(Filter, i, 1) = vbNullChar
         End Select
      Next
      .lpstrFilter = StrPtr(Filter)
      .nFilterIndex = FilterIndex
   
      ' FileTitle is simply the unqualified filename, which is
      ' easy enough to parse out so we can just ignore.
      .lpstrFileTitle = 0 ' String$(MAX_FILE, 0)
      .nMaxFileTitle = 0  ' MAX_FILE
      
      ' Pad file and file title buffers to maximum path
      FileName = Left$(FileName & String$(MAX_PATH, vbNullChar), MAX_PATH)
      .lpstrFile = StrPtr(FileName)
      .nMaxFile = MAX_PATH
      
      ' All other fields set to zero
      
      If GetOpenFileName(opfile) Then
         ' All went exactly as expected.
         Success = True
      ElseIf (CommDlgExtendedError() = FNERR_BUFFERTOOSMALL) And (MultiSelect = True) Then
         ' See: http://www.codeproject.com/KB/dialog/pja_multiselect.aspx
         ' Use our own shadow buffer.
         Success = True
      End If
      
      If Success Then
         ' Return results from overflow buffer if needed.
         If MultiSelect Then
            FileName = TrimNull(m_FolderEx) & vbNullChar & _
                       TrimNull(m_FileEx) & vbNullChar & vbNullChar
            GetOpenName = MultiSelectFiles(TheFiles)
         Else
            FileName = PointerToStringW(.lpstrFile)
            GetOpenName = 1
         End If
         
         ' Break out the Read-Only flag from others
         ReadOnly = CBool(.Flags And OFN_READONLY)
         Flags = .Flags
         
         ' Return the filter index, and actual filter selected.
         FilterIndex = .nFilterIndex
'         Filter = FilterLookup(.lpstrFilter, FilterIndex)
         
      Else
         Debug.Print "CommDlgExtendedError = &h"; Hex$(CommDlgExtendedError())
         GetOpenName = 0
         FileName = sEmpty
         Flags = 0
         FilterIndex = -1
         Filter = sEmpty
         m_FileEx = sEmpty
         m_FolderEx = sEmpty
      End If
   End With
End Function

Public Function GetSaveName(FileName As String, _
                           Optional FileTitle As String, _
                           Optional OverWritePrompt As Boolean = True, _
                           Optional Filter As String = "All (*.*)| *.*", _
                           Optional FilterIndex As Long = 1, _
                           Optional InitDir As String, _
                           Optional DlgTitle As String, _
                           Optional DefaultExt As String, _
                           Optional Owner As Long = -1, _
                           Optional Flags As Long) As Boolean

   Dim opfile As OpenFileNameType, s As String
   With opfile
      .lStructSize = Len(opfile)

      ' Add in specific flags and strip out non-VB flags
      .Flags = (-OverWritePrompt * OFN_OVERWRITEPROMPT) Or _
               OFN_HIDEREADONLY Or _
               (Flags And CLng(Not (OFN_ENABLEHOOK Or _
                                    OFN_ENABLETEMPLATE)))
      ' Owner can take handle of owning window
      If Owner <> -1 Then .hwndOwner = Owner
      ' InitDir can take initial directory string
      .lpstrInitialDir = StrPtr(InitDir)
      ' DefaultExt can take default extension
      .lpstrDefExt = StrPtr(DefaultExt)
      ' DlgTitle can take dialog box title
      .lpstrTitle = StrPtr(DlgTitle)

      ' Make new filter with bars (|) replacing nulls and double null at end
      Dim ch As String, i As Integer
      For i = 1 To Len(Filter)
         ch = Mid$(Filter, i, 1)
         If ch = "|" Or ch = ":" Then
            s = s & vbNullChar
         Else
            s = s & ch
         End If
      Next
      ' Put double null at end
      s = s & vbNullChar & vbNullChar
      .lpstrFilter = StrPtr(s)
      .nFilterIndex = FilterIndex

      ' Pad file and file title buffers to maximum path
      s = FileName & String$(MAX_PATH - Len(FileName), 0)
      .lpstrFile = StrPtr(s)
      .nMaxFile = MAX_PATH
      s = FileTitle & String$(MAX_PATH - Len(FileTitle), 0)
      .lpstrFileTitle = StrPtr(s)
      .nMaxFileTitle = MAX_PATH
      ' All other fields zero

      If GetSaveFileName(opfile) Then
         GetSaveName = True
         FileName = LPWSTRtoStr(.lpstrFile) ' StrZToStr(.lpstrFile)
         FileTitle = LPWSTRtoStr(.lpstrFileTitle) 'StrZToStr(.lpstrFileTitle)
         Flags = .Flags
         ' Return the filter index
         FilterIndex = .nFilterIndex
         ' Look up the filter the user selected and return that
'         Filter = FilterLookup(.lpstrFilter, FilterIndex)
      Else
         GetSaveName = False
         FileName = sEmpty
         FileTitle = sEmpty
         Flags = 0
         FilterIndex = 0
         Filter = sEmpty
      End If
   End With
End Function

Public Function MultiSelectFiles(TheFiles() As String) As Long
   Dim iStart As Long, iEnd As Long
   Dim nCount As Long
   ' Make sure we have data.
   If Len(m_FolderEx) > 0 And Len(m_FileEx) > 0 Then
      ' If more than one file is selected, first char will be quote.
      iStart = InStr(m_FileEx, """")
      If iStart = 1 Then
         Do
            iEnd = InStr(iStart + 1, m_FileEx, """")
            If iEnd = 0 Then Exit Do
            ' Increase size of holding array, and extract this file.
            nCount = nCount + 1
            ReDim Preserve TheFiles(0 To nCount - 1) As String
            TheFiles(nCount - 1) = PathCombine(TrimNull(m_FolderEx), _
                                               Mid$(m_FileEx, iStart + 1, iEnd - iStart - 1))
            iStart = InStr(iEnd + 1, m_FileEx, """")
         Loop While iStart
         MultiSelectFiles = nCount
         
      Else
         ' Just return the single file.
         ReDim TheFiles(0 To 0) As String
         TheFiles(0) = PathCombine(TrimNull(m_FolderEx), TrimNull(m_FileEx))
         MultiSelectFiles = 1
      End If
   End If
End Function

' =====================================================================
'  Private Methods
' =====================================================================
Private Function FilterLookup(ByVal sFilters As String, ByVal iCur As Long) As String
   Dim iStart As Long
   Dim iEnd As Long
   Dim s As String
   
   iStart = 1
   If sFilters = sEmpty Then Exit Function
   Do
      ' Cut out both parts marked by null character
      iEnd = InStr(iStart, sFilters, vbNullChar)
      If iEnd = 0 Then Exit Function
      iEnd = InStr(iEnd + 1, sFilters, vbNullChar)
      If iEnd Then
         s = Mid$(sFilters, iStart, iEnd - iStart)
      Else
         s = Mid$(sFilters, iStart)
      End If
      iStart = iEnd + 1
      If iCur = 1 Then
         ' Replace null with pipe symbol to be more VBish.
         iStart = InStr(s, vbNullChar)
         If iStart Then Mid$(s, iStart, 1) = "|"
         FilterLookup = s
         Exit Function
      End If
      iCur = iCur - 1
   Loop While iCur
End Function

Private Function FncPtr(ByVal lpFunction As Long) As Long
   ' Return what was sent using AddressOf
   FncPtr = lpFunction
End Function

Private Function OFNHookProc(ByVal hDlg As Long, ByVal uMsg As Long, ByVal wParam As Long, ByVal lParam As Long) As Long
   Dim ofn As OFNOTIFY
   Dim opfile As OpenFileNameType
   Dim TestFiles() As String
   Dim nFiles As Long
   Dim i As Long
   Dim Msg As String
   
   'Debug.Print "uMsg = &h"; Hex$(uMsg)
   Select Case uMsg
      Case WM_INITDIALOG
         OFNHookProc = 1 'true, not strictly needed.

      Case WM_NOTIFY
         ' The OFNOTIFY struct is passed in the lParam of this message.
         Call CopyMemory(ofn, ByVal lParam, Len(ofn))
         ' A pointer to an OPENFILENAME structure is passed in OFNOTIFY.
         Call CopyMemory(opfile, ByVal ofn.lpOFN, Len(opfile))
         'Debug.Print "  ofn.hdr.code = &h"; Hex$(ofn.hdr.code)

         ' Branch based on notification code.
         Select Case ofn.hdr.code
            Case CDN_FILEOK
               Call OFNHookReadFiles(hDlg)
               ' This is our chance to say whether the file selection is valid.
               If m_MustExist Then
                  ' Parse out selected files into array.
                  nFiles = MultiSelectFiles(TestFiles)

                  ' Must reject non-existant files!
                  For i = 0 To nFiles - 1
                     If FileExists(TestFiles(i)) = False Then
                        Msg = TestFiles(i) & vbCrLf & "File not found." & vbCrLf & _
                              "Please verify the correct file name was given."
                        MsgBox Msg, vbExclamation, PointerToStringW(opfile.lpstrTitle)
                        ' Note: Use hDlg, not GetParent(hDlg)!
                        Call SetWindowLong(hDlg, DWL_MSGRESULT, 1)
                        OFNHookProc = 1
                        Exit For
                     End If
                  Next i
               End If
               Debug.Print "CDN_FILEOK"
               
            Case CDN_FOLDERCHANGE
               Call OFNHookReadFolder(hDlg)
               Debug.Print "CDN_FOLDERCHANGE: "; m_FolderEx
               
            Case CDN_SELCHANGE
               Call OFNHookReadFiles(hDlg)
               Debug.Print "CDN_SELCHANGE:    "; m_FileEx
               
            Case CDN_INITDONE
               Debug.Print "CDN_INITDONE"
               
            Case Else
               Debug.Print "Unknown notification: &h:" & Hex$(ofn.hdr.code)
         End Select
   End Select
End Function

Private Sub OFNHookReadFiles(ByVal hDlg As Long)
   Dim hWnd As Long
   Dim nChars As Long
   ' Find handle to dialog window.
   hWnd = GetParent(hDlg)
   ' Get size of buffer required for filespec.
   nChars = SendMessage(hWnd, CDM_GETSPEC, 0&, ByVal StrPtr(m_FileEx))
   ' Get the full buffer for the filespec(s)
   If nChars > 0 Then
      m_FileEx = Space$(nChars)
      Call SendMessage(hWnd, CDM_GETSPEC, nChars, ByVal StrPtr(m_FileEx))
   End If
End Sub

Private Sub OFNHookReadFolder(ByVal hDlg As Long)
   Dim hWnd As Long
   Dim nChars As Long
   ' Find handle to dialog window.
   hWnd = GetParent(hDlg)
   ' Get size of buffer required for path.
   nChars = SendMessage(hWnd, CDM_GETFOLDERPATH, 0&, ByVal StrPtr(m_FolderEx))
   ' Get the full buffer for the path.
   If nChars > 0 Then
      m_FolderEx = Space$(nChars)
      Call SendMessage(hWnd, CDM_GETFOLDERPATH, nChars, ByVal StrPtr(m_FolderEx))
   End If
End Sub

Private Function PathCombine(ByVal Directory As String, ByVal File As String) As String
   Dim Buffer As String
   ' Concatenates two strings that represent properly formed
   ' paths into one path, as well as any relative path pieces.
   Buffer = String$(MAX_PATH, 0)
   If PathCombineW(StrPtr(Buffer), StrPtr(Directory), StrPtr(File)) Then
      PathCombine = TrimNull(Buffer)
   End If
End Function

Private Function PointerToStringA(ByVal lpStringA As Long) As String
   Dim Buffer() As Byte
   Dim nLen As Long
   If lpStringA Then
      nLen = lstrlenA(ByVal lpStringA)
      If nLen Then
         ReDim Buffer(0 To (nLen - 1)) As Byte
         CopyMemory Buffer(0), ByVal lpStringA, nLen
         PointerToStringA = StrConv(Buffer, vbUnicode)
      End If
   End If
End Function

Public Function PointerToStringW(ByVal lpStringW As Long) As String
   Dim Buffer() As Byte
   Dim nLen As Long
   If lpStringW Then
      nLen = lstrlenW(lpStringW) * 2
      If nLen Then
         ReDim Buffer(0 To (nLen - 1)) As Byte
         CopyMemory Buffer(0), ByVal lpStringW, nLen
         PointerToStringW = Buffer
      End If
   End If
End Function

Private Function TrimNull(ByVal StrZ As String) As String
   TrimNull = Left$(StrZ, InStr(StrZ & vbNullChar, vbNullChar) - 1)
End Function

' This routine exists only to ensure the CASE of these constants
' isn't altered while editting code, as can happen with Enums.
#If False Then
Private Sub ForceEnumCase()
   Const OFN_READONLY As Long = &H1
   Const OFN_OVERWRITEPROMPT As Long = &H2
   Const OFN_HIDEREADONLY As Long = &H4
   Const OFN_NOCHANGEDIR As Long = &H8
   Const OFN_SHOWHELP As Long = &H10
   Const OFN_ENABLEHOOK As Long = &H20
   Const OFN_ENABLETEMPLATE As Long = &H40
   Const OFN_ENABLETEMPLATEHANDLE As Long = &H80
   Const OFN_NOVALIDATE As Long = &H100
   Const OFN_ALLOWMULTISELECT As Long = &H200
   Const OFN_EXTENSIONDIFFERENT As Long = &H400
   Const OFN_PATHMUSTEXIST As Long = &H800
   Const OFN_FILEMUSTEXIST As Long = &H1000
   Const OFN_CREATEPROMPT As Long = &H2000
   Const OFN_SHAREAWARE As Long = &H4000
   Const OFN_NOREADONLYRETURN As Long = &H8000
   Const OFN_NOTESTFILECREATE As Long = &H10000
   Const OFN_NONETWORKBUTTON As Long = &H20000
   Const OFN_NOLONGNAMES As Long = &H40000
   Const OFN_EXPLORER As Long = &H80000
   Const OFN_NODEREFERENCELINKS As Long = &H100000
   Const OFN_LONGNAMES As Long = &H200000
   Const OFN_ENABLEINCLUDENOTIFY As Long = &H400000
   Const OFN_ENABLESIZING As Long = &H800000
   Const OFN_DONTADDTORECENT As Long = &H2000000
   Const OFN_FORCESHOWHIDDEN As Long = &H10000000
   
   Const OFN_SHAREFALLTHROUGH As Long = 2
   Const OFN_SHARENOWARN As Long = 1
   Const OFN_SHAREWARN As Long = 0

   Const OFN_EX_NOPLACESBAR As Long = &H1
End Sub
#End If




