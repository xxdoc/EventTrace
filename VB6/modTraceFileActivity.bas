Attribute VB_Name = "modTraceFileActivity"
Option Explicit
'*****************************************
'modTraceFileActivity
'
'Implements an NT Kernel Logger to monitor file activity.
'
'You can use this module independently; final activity records
'are stored in the ActivityLog structure, which you can display
'how you like. This demo implements a virtual ListView on the
'main form. Note: In a separate project, take care to note
'everything that happens on starting/stopping, there's a little
'more to it than calling Init/End.
'
'Requires: modEventTrace.bas (Windows Event Tracing definitions)
'          modThreadProcID.bas (Module to identify a process based on id)
'
'(c) 2022 Jon Johnson (aka fafalone)

Private dbgmax As Long, rdmax As Long, obmax As Long, tdmax As Long
Public szmax As Long
Private Const sRdProc = "(rundown)"



Public bEnableCSwitch As Boolean
Private tidCur As Long
Private pidCur As Long
Private pidLast As Long

Public Const MAX_PATH As Long = 260&

Public bIsWinVistaOrGreater As Boolean
Public bIsWin7OrGreater As Boolean
Public bIsWin8OrGreater As Boolean
Public bIsWin10OrGreater As Boolean


Public hBtnPause As Long
Public bPauseCol As Long

Public bStopping As Boolean

Public bInitRdDone As Boolean
Public bUseInitRd As Boolean
Public bUseEndRd As Boolean

Public bMergeSameFile As Boolean
Public bMergeSameCode As Boolean

'Filters:
Public bEventCreate As Boolean
Public bEventRead As Boolean
Public bEventWrite As Boolean
Public bEventDelete As Boolean
Public bEventQuery As Boolean
Public bEventSetInfo As Boolean
Public bEventRename As Boolean
Public bEventDirEnum As Boolean
Public bEventFsctl As Boolean
Public bEventDiskIO As Boolean
Public bEventNoRundown As Boolean

Public DiskIOExclusive As Boolean
Public bSupDIOE As Boolean

Public sFilterPath As String
Public sFilterPathExc As String
Public sFilterFile As String
Public sFilterFileExc As String
Public sFilterProc As String
Public bProcIsInc As Boolean
Public bIgnoreSelf As Boolean
Public pidSelf As Long
Public tidSelfMain As Long
Public tidSelfProcEvt As Long

Private sFlPath() As String
Private sFlPathX() As String
Private sFlFile() As String
Private sFlFileX() As String
Private sFlProc() As String
Private lFlPid() As Long
Private nFlPath As Long
Private nFlPathX As Long
Private nFlFile As Long
Private nFlFileX As Long
Private nFlProc As Long
Private nFlPid As Long

Public Enum ActivityType
    atFileCreate = 0
    atFileAccess = 1 'Used for DiskIo_ReadWrite not linked to a FileCreate event
    atFileQuery = 2
    atFileDelete = 3
    atFileRename = 4
    atFileSetInfo = 5
    atDirEnum = 6
    atDirChange = 7
    atDirDel = 8
    atDirRename = 9
    atDirSetLink = 10
    atDirNotify = 11
    atFileFsctl = 12
    atRundown = 13
    atOpenFileRW = 14
End Enum
Public Type ActivityEvent
    cRead As Currency
    cWrite As Currency
    OpenCount As Long
    DeleteCount As Long
    dtMod As SYSTEMTIME
    intProcId As Long 'Internal data tracking
    '44 bytes
    bChanged As Boolean 'Only for DispActLog
    iType As ActivityType
    iIcon As Long
    dtStart As SYSTEMTIME
    intListIdx As Long
    intFileObj As Currency
    bClosed As Boolean
    iCode As Byte
    sProcess As String
    intProcPath As String
    sFile As String
    sMisc As String
End Type
Public ActivityLog() As ActivityEvent
Public nAcEv As Long
Public Const cbALCompRgn = 44& 'The first 44 bytes of the structure are deliberately ordered that way
                               'to check for changes using RtlCompareMemory

'The callback and the display are in separate threads. When they both try to read the
'ActivityLog structure, a crash results. We'll need to keep a separate one for the
'display and synchronize them in a critical section.
Public DispActLog() As ActivityEvent
Public nDspAc As Long

Private tTraceProps As EtpKernelTrace

Public sFullLog As String
Public sFullLogLocal As String
Public cbLog As Long

Public Const gTraceName = "TraceFileActivVB"
Public SelectedGuid As GUID
Public SelectedName As String
Public bUseNewLogMode As Boolean

Public gTraceHandle As Currency
Public gSessionHandle As Currency
Public bTraceRunning As Boolean
Public hProcThread As Long
Public hProcThread2 As Long
Public hProcThreadId As Long
Public ptRes As Long
Public cbPointer As Long

'Critical Section usage:
'Every time you read or write a variable shared between threads, it must be done
'in a critical section. Currently in this demo, that means any time you touch
'ActivityLog or nAcEv, it must be inside critical section oCS (which you must leave,
'otherwise the application will lock, so make sure any error handler you might
'jump into has it too if neccessary). Any time you touch sFullLog or cbLog, that
'must be inside oCS2.
'This demo is structured such that Form1 and calls to InitTrace/EndTrace/FlushTrace
'make up the main thread, while all event receiving and processing is in a separate
'thread. DispActLog/nDspAc are owned by the main thread, and synchronized to
'ActivityLog and nAcEv. Since we can't touch ActivityLog in the 2nd thread while the
'sync happens, we wind up with a ton of Enter/Leave calls. I'm considering ways to
'simplify it.
Public Type CRITICAL_SECTION
    pDebugInfo      As Long
    LockCount       As Long
    RecursionCount  As Long
    OwningThread    As Long
    LockSemaphore   As Long
    SpinCount       As Long
End Type
Public oCS As CRITICAL_SECTION
Public oCS2 As CRITICAL_SECTION

Private Type FileNameRec
    FileObject As Currency
    FileName As String
    pid As Long
    tid As Long
End Type
Private FileNameRecs() As FileNameRec
Private nFNR As Long
Private RundownRecs() As FileNameRec
Private nFRR As Long

Private Type FileRWActivityRecord
    DiskNumber As Long
    FileObject As Currency
    IRP As Currency
    ProcessID As Long
    FileKey As Currency
    FileIndex As Long
    ReadBytes As Currency
    WriteBytes As Currency
    DriveLetter As String
    PathName As String
    ProcessName As String
    ProcessPath As String
    OpenCount As Long
    DeleteCount As Long
    pid As Long
End Type
Private FileRWRecs() As FileRWActivityRecord
Private nFRW As Long

Private Type DirActionRecord
    DiskNumber As Long
    FileObject As Currency
    IRP As Currency
    ProcessID As Long
    FileKey As Currency
    FileIndex As Long
    Flags As Long
    DriveLetter As String
    PathName As String
End Type
Private DirRecords() As DirActionRecord
Private nDirRec As Long

Private Type FileAttribQueryRecord
    DiskNumber As Long
    FileObject As Currency
    IRP As Currency
    ProcessID As Long
    FileKey As Currency
    FileIndex As Long
    Flags As Long
    DriveLetter As String
    PathName As String
End Type
Private QueryRecords() As FileAttribQueryRecord
Private nQRec As Long

Private Type DiskIoRecord
    FileObject As Currency
    IRP As Currency
    IssuingThread As Long
    IssuingProc As Long
    BytesRead As Currency
    BytesWritten As Currency
    dwIrpFlags As Long
End Type
Private DiskIoRecords() As DiskIoRecord
Private nDIOR As Long

Private Type VolData
    sLetter As String
    sName As String
End Type
Private VolMap() As VolData
Private bSetVM As Boolean

Public Const MAX_LONG_L As Long = 2147483647

Public Const READ_CONTROL As Long = &H20000
Public Const MAXIMUM_ALLOWED = &H2000000
Public Const STANDARD_RIGHTS_REQUIRED = &HF0000
Public Const STANDARD_RIGHTS_READ As Long = READ_CONTROL
Public Const STANDARD_RIGHTS_WRITE As Long = READ_CONTROL
Public Const STANDARD_RIGHTS_EXECUTE As Long = READ_CONTROL
Public Const STANDARD_RIGHTS_ALL As Long = &H1F0000
Public Const SPECIFIC_RIGHTS_ALL As Long = &HFFFF
Public Const SYNCHRONIZE As Long = &H100000

Public Const FORMAT_MESSAGE_FROM_SYSTEM = &H1000
Public Const FORMAT_MESSAGE_IGNORE_INSERTS = &H200
Public Const FORMAT_MESSAGE_FROM_HMODULE = &H800
Public Const PROCESS_ALL_ACCESS As Long = (STANDARD_RIGHTS_REQUIRED Or SYNCHRONIZE Or &HFFF&)
Public Const PROCESS_CREATE_THREAD = &H2   ' Enables using the process handle in the CreateRemoteThread function to create a thread in the process.
Public Const PROCESS_DUP_HANDLE = &H40   ' Enables using the process handle as either the source or target process in the DuplicateHandle function to duplicate a handle
Public Const PROCESS_QUERY_INFORMATION = &H400 ' Enables using the process handle in the GetExitCodeProcess and GetPriorityClass functions to read information from the process object.
Public Const PROCESS_SET_INFORMATION = &H200 ' Enables using the process handle in the SetPriorityClass function to set the priority class of the process.
Public Const PROCESS_TERMINATE = &H1 ' Enables using the process handle in the TerminateProcess function to terminate the process.
Public Const PROCESS_VM_OPERATION = &H8 ' Enables using the process handle in the VirtualProtectEx and WriteProcessMemory functions to modify the virtual memory of the process.
Public Const PROCESS_VM_READ = &H10     ' Enables using the process handle in the ReadProcessMemory function to read from the virtual memory of the process.
Public Const PROCESS_VM_WRITE = &H20 ' Enables using the process handle in the WriteProcessMemory function to write to the virtual memory of the process.

'Access rights for thread.
Public Enum ThreadAccess
    THREAD_DIRECT_IMPERSONATION = &H200
    THREAD_GET_CONTEXT = &H8
    THREAD_IMPERSONATE = &H100
    THREAD_QUERY_INFORMATION = &H40
    THREAD_QUERY_LIMITED_INFORMATION = &H800
    THREAD_SET_CONTEXT = &H10
    THREAD_SET_INFORMATION = &H20
    THREAD_SET_LIMITED_INFORMATION = &H400
    THREAD_SET_THREAD_TOKEN = &H80
    THREAD_SUSPEND_RESUME = &H2
    THREAD_TERMINATE = &H1
End Enum

Public Const DUPLICATE_SAME_ACCESS As Long = &H2

Public Const WAIT_ABANDONED = &H80
Public Const WAIT_OBJECT_0 = 0&
Public Const WAIT_TIMEOUT = &H102
Public Const WAIT_FAILED = &HFFFFFFFF

Public hThreadWait As Long

Private Declare Function CloseHandle Lib "kernel32" (ByVal hObject As Long) As Long
Public Declare Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (Destination As Any, Source As Any, ByVal Length As Long)
Public Declare Sub CoTaskMemFree Lib "ole32.dll" (ByVal pv As Long)
Public Declare Function InitializeCriticalSectionAndSpinCount Lib "kernel32" (lpCriticalSection As CRITICAL_SECTION, ByVal dwSpinCount As Long) As Long
Public Declare Sub EnterCriticalSection Lib "kernel32" (lpCriticalSection As CRITICAL_SECTION)
Public Declare Sub LeaveCriticalSection Lib "kernel32" (lpCriticalSection As CRITICAL_SECTION)
Public Declare Sub DeleteCriticalSection Lib "kernel32" (lpCriticalSection As CRITICAL_SECTION)
Private Declare Function DuplicateHandle Lib "kernel32" (ByVal hSourceProcessHandle As Long, ByVal hSourceHandle As Long, ByVal hTargetProcessHandle As Long, lpTargetHandle As Long, ByVal dwDesiredAccess As Long, ByVal bInheritHandle As Long, ByVal dwOptions As Long) As Long
Private Declare Function FormatMessageW Lib "kernel32" (ByVal dwFlags As Long, lpSource As Any, ByVal dwMessageId As Long, ByVal dwLanguageId As Long, ByVal StrPtr As Long, ByVal nSize As Long, Arguments As Long) As Long
Public Declare Function GetCurrentProcessId Lib "kernel32" () As Long
Public Declare Function GetCurrentThreadId Lib "kernel32" () As Long
Private Declare Sub GetLocalTime Lib "kernel32" (lpSystemTime As SYSTEMTIME)
Public Declare Function GetProcessIdOfThread Lib "kernel32" (ByVal Thread As Long) As Long
Public Declare Function IsWow64Process Lib "kernel32" (ByVal hProcess As Long, Wow64Process As Long) As Long
Private Declare Function IsEqualGUID Lib "ole32" (riid1 As GUID, riid2 As GUID) As Long
Public Declare Function lstrlenW Lib "kernel32" (lpString As Any) As Long
Private Declare Function OpenThread Lib "kernel32" (ByVal dwDesiredAccess As ThreadAccess, ByVal bInheritHandle As Long, ByVal dwThreadId As Long) As Long
Public Declare Function OpenProcess Lib "kernel32" (ByVal dwDesiredAccess As Long, ByVal bInheritHandle As Long, ByVal dwProcessId As Long) As Long
Private Declare Function PathFindFileName Lib "shlwapi" Alias "PathFindFileNameW" (ByVal pPath As Long) As Long
Private Declare Function PathFileExists Lib "shlwapi" Alias "PathFileExistsW" (ByVal lpszPath As Long) As Boolean
Private Declare Function PathIsDirectory Lib "shlwapi" Alias "PathIsDirectoryW" (ByVal lpszPath As Long) As Boolean
Private Declare Function PathMatchSpec Lib "shlwapi" Alias "PathMatchSpecW" (ByVal pszFileParam As Long, ByVal pszSpec As Long) As Boolean
Private Declare Function QueryDosDevice Lib "kernel32" Alias "QueryDosDeviceA" (ByVal lpDeviceName As String, ByVal lpTargetPath As String, ByVal ucchMax As Long) As Long
Private Declare Function Sleep Lib "kernel32" (ByVal dwMilliseconds As Long) As Long
Private Declare Function SysReAllocString Lib "oleaut32.dll" (ByVal pBSTR As Long, Optional ByVal pszStrPtr As Long) As Long
Public Declare Function SysReAllocStringLen Lib "oleaut32.dll" (ByVal pBSTR As Long, ByVal pszStrPtr As Long, ByVal lLen As Long) As Long
Public Declare Function UpdateWindow Lib "user32" (ByVal hWnd As Long) As Long
Public Declare Function WaitForSingleObject Lib "kernel32" (ByVal hHandle As Long, ByVal dwMilliseconds As Long) As Long
Private Declare Sub ZeroMemory Lib "ntdll" Alias "RtlZeroMemory" (dest As Any, ByVal numBytes As Long)

'This project involved doing most of the work in compiled form, so I used a textbox like Debug.Print.
'Multithreading made this more complicated, but the use of a critical sections made this workable.
Public Sub PostLog(sMsg As String)
EnterCriticalSection oCS2
sMsg = "[" & Format$(Now, "Hh:nn:Ss") & "] " & sMsg
sFullLog = sFullLog & sMsg & vbCrLf
LeaveCriticalSection oCS2
End Sub

'=====================================================================
'Common utility functions
Public Function LPWSTRtoStr(lPtr As Long, Optional ByVal fFree As Boolean = True) As String
SysReAllocString VarPtr(LPWSTRtoStr), lPtr
If fFree Then
    Call CoTaskMemFree(lPtr)
End If
End Function

Public Function TrimNullW(startstr As String) As String
TrimNullW = Left$(startstr, lstrlenW(ByVal StrPtr(startstr)))
End Function

Public Function FARPROC(pfn As Long) As Long
  FARPROC = pfn
End Function

Public Function WCHARtoStr(aCh() As Integer) As String
Dim i As Long
Dim sz As String
Dim bStart As Boolean
For i = LBound(aCh) To UBound(aCh)
    If aCh(i) <> 0 Then
        sz = sz & ChrW(CLng(aCh(i)))
        bStart = True
    Else
        If bStart = False Then sz = sz & "0"
    End If
Next
If bStart = False Then
    WCHARtoStr = "<unknown or none>"
Else
    WCHARtoStr = sz
End If
End Function
'---------------------------------------------------------------------

'=====================================================================
'Preparation
'First, we need to set up processing for the data we'll receive. Path names passed to
'event tracing are not in the standard Win32 format of C:\folder\file.ext. they're
'instead passed as \Device\HarddiskVolume1\folder\file.ext. To convert those to normal
'paths, before running we map out all drives; we query the paths for A:\ to Z:\ and
'store any we find...
Private Sub MapVolumes()
'Map out \Device\Harddiskblahblah
Dim sDrive As String
Dim i As Long, j As Long
Dim sBuffer As String
ReDim VolMap(0)
Dim tmpMap() As VolData
Dim nMap As Long, nfMap As Long
Dim lIdx As Long
Dim lnMax As Long
Dim cb As Long
For lIdx = 0 To 25
    sDrive = Chr$(65 + lIdx) & ":"
    sBuffer = String$(1000, vbNullChar)
    cb = QueryDosDevice(sDrive, sBuffer, Len(sBuffer))
    If cb Then
        ReDim Preserve tmpMap(nMap)
        tmpMap(nMap).sLetter = sDrive
        tmpMap(nMap).sName = TrimNullW(sBuffer)
        nMap = nMap + 1
    End If
Next
'Next we need to sort the array so e.g. 10 will always come before 1
'We'll find the longest ones, add any of that length, then add any
'of 1 char shorter, until we've added all items
For i = 0 To (nMap - 1)
    If Len(tmpMap(i).sName) > lnMax Then lnMax = Len(tmpMap(i).sName)
Next i
ReDim VolMap(nMap - 1)
For i = lnMax To 1 Step -1
    For j = 0 To UBound(tmpMap)
        If Len(tmpMap(j).sName) = i Then
            VolMap(nfMap).sName = tmpMap(j).sName
            VolMap(nfMap).sLetter = tmpMap(j).sLetter
            nfMap = nfMap + 1
        End If
    Next j
    If nfMap = nMap Then Exit For
Next i
bSetVM = True
End Sub

'Then we can convert path names by running through the ones we got and replacing any
'occurences of them. The array is presorted so 10 comes before 1.
Public Function ConvertNtPathToDosPath(sPath As String) As String
If sPath = "" Then Exit Function
 
Dim i As Long
ConvertNtPathToDosPath = sPath
For i = 0 To UBound(VolMap)
    ConvertNtPathToDosPath = Replace08(ConvertNtPathToDosPath, VolMap(i).sName, VolMap(i).sLetter, 1, 1)
Next
End Function

'For debug purposes, here's a function to print our map to the log.
Public Sub DumpMap()
MapVolumes
Dim i As Long
For i = 0 To UBound(VolMap)
    PostLog "Mapped " & VolMap(i).sLetter & " to " & VolMap(i).sName
Next i
End Sub

Public Sub DumpNames()
Dim i As Long
PostLog "Dumping FileIo_Name records, n=" & nFNR
If nFNR Then
    For i = 0 To UBound(FileNameRecs)
        PostLog FileNameRecs(i).FileName
    Next
End If
End Sub

'We collect a lot of data sometimes; might want to clear it, especially starting a new trace.
Public Sub ClearBuffers()
'Clears all existing event records and the activity log
ReDim DispActLog(0)
nDspAc = 0&
ReDim ActivityLog(0)
nAcEv = 0&
ReDim FileNameRecs(0)
nFNR = 0&
ReDim RundownRecs(0)
nFRR = 0&
ReDim FileRWRecs(0)
nFRW = 0&
ReDim DirRecords(0)
nDirRec = 0&
ReDim QueryRecords(0)
nQRec = 0&
ReDim DiskIoRecords(0)
nDIOR = 0&
End Sub

'Because of the volume of data generated from watching low level activity, filters are
'practically a neccessity. The main filter strings that are declared as public should be
'filled in by the caller, then we process them into arrays for convenience in checking
'them. Most of the filters are explained on the form already, but to go into more detail
'on the process filter, you can use process ids within the list, e.g.
'chrome.exe|vb6.exe|>123 to include/exclude activity originating from Chrome, VB6, and
'whichever process is currently identified by pid 123.
Public Sub SetFilters()
nFlPath = 0&
nFlPathX = 0&
nFlFile = 0&
nFlFileX = 0&
nFlProc = 0&
nFlPid = 0&
ReDim lFlPid(0)
Dim sBar As String
sBar = "|"
If sFilterPath <> "" Then
    sFilterPath = Replace$(sFilterPath, "�", sBar)
    sFlPath = Split(sFilterPath, sBar)
    nFlPath = UBound(sFlPath) + 1 'This will also serve as an enable flag
End If
If sFilterPathExc <> "" Then
    sFilterPathExc = Replace$(sFilterPathExc, "�", sBar)
    sFlPathX = Split(sFilterPathExc, sBar)
    nFlPathX = UBound(sFlPathX) + 1 'This will also serve as an enable flag
End If
If sFilterFile <> "" Then
    sFilterFile = Replace$(sFilterFile, "�", sBar)
    sFlFile = Split(sFilterFile, sBar)
    nFlFile = UBound(sFlFile) + 1 'This will also serve as an enable flag
End If
If sFilterFileExc <> "" Then
    sFilterFileExc = Replace$(sFilterFileExc, "�", sBar)
    sFlFileX = Split(sFilterFileExc, sBar)
    nFlFileX = UBound(sFlFileX) + 1 'This will also serve as an enable flag
End If
If sFilterProc <> "" Then
    sFilterProc = Replace$(sFilterProc, "�", sBar)
    Dim sProcI() As String
    sProcI = Split(sFilterProc, sBar)
    Dim i As Long
    For i = 0 To UBound(sProcI)
        If Left$(sProcI(i), 1) = ">" Then
            ReDim Preserve lFlPid(nFlPid)
            lFlPid(nFlPid) = CLng(Mid$(sProcI(i), 2&))
            nFlPid = nFlPid + 1&
        Else
            ReDim Preserve sFlProc(nFlProc)
            sFlProc(nFlProc) = sProcI(i)
            nFlProc = nFlProc + 1&
        End If
    Next i
End If
pidSelf = GetCurrentProcessId()
tidSelfMain = GetCurrentThreadId()

End Sub

'Now here's an implementation that determines whether an item is included:
Public Function ItemIncluded(sPath As String, bIsProcess As Boolean, Optional lPid As Long = 0&, Optional bDir As Boolean = False) As Boolean
If bIgnoreSelf Then
    If lPid = pidSelf Then Exit Function
End If
If nFlPath + nFlPathX + nFlFile + nFlFileX + nFlProc + nFlPid = 0& Then
    'No filters enabled
    ItemIncluded = True
    Exit Function
End If
Dim i As Long, j As Long

If bIsProcess Then
    If nFlPid Then
        For i = 0 To UBound(lFlPid)
            If lPid = lFlPid(i) Then
                If bProcIsInc = True Then
                    ItemIncluded = True
                End If
                Exit Function
            End If
        Next i
    End If
    If nFlProc Then
        For i = 0 To UBound(sFlProc)
            If PathMatchSpec(StrPtr(sPath), StrPtr(sFlProc(i))) Then
                If bProcIsInc = True Then
                    ItemIncluded = True
                End If
                Exit Function
            End If
        Next i
    End If
    If bProcIsInc = False Then
        'If it's an exclusion filter, and hasn't been matched, include it
        ItemIncluded = True
    End If
Else
    Dim sName As String, lpName As Long
    If nFlPath Then
        ItemIncluded = False
        For i = 0 To UBound(sFlPath)
            If PathInPath(sFlPath(i), sPath) Then
                ItemIncluded = True
                Exit For
            End If
        Next i
        If ItemIncluded = False Then Exit Function
    Else
        ItemIncluded = True
    End If
    If nFlPathX Then
        For i = 0 To UBound(sFlPathX)
            If PathInPath(sFlPathX(i), sPath) Then
                ItemIncluded = False
                Exit Function
            End If
        Next i
    End If
        
    If bDir = False Then
        If nFlFile Or nFlFileX Then
            lpName = PathFindFileName(StrPtr(sPath))
            If lpName Then
                sName = LPWSTRtoStr(lpName)
            Else
                'Not a file?
                ItemIncluded = True
                Exit Function
            End If
        End If
        If nFlFile Then
            ItemIncluded = False
            For i = 0 To UBound(sFlFile)
                If PathMatchSpec(StrPtr(sName), StrPtr(sFlFile(i))) Then
                    ItemIncluded = True
                    Exit For
                End If
            Next i
            If ItemIncluded = False Then Exit Function
        Else
            ItemIncluded = True
        End If
        If nFlFileX Then
            For i = 0 To UBound(sFlFileX)
                If PathMatchSpec(StrPtr(sName), StrPtr(sFlFileX(i))) Then
                    ItemIncluded = False
                    Exit For
                End If
            Next i
        End If
    End If
End If
End Function
Private Function PathInPath(sCompare As String, sCheck As String) As Boolean
'Checks if path sCheck is in path sCompare
If Len(sCompare) > Len(sCheck) Then Exit Function 'A shorter path can't be in a longer one
Dim sCo As String, sCh As String
sCo = LCase02(sCompare): sCh = LCase02(sCheck)
If Right$(sCo, 1&) = "\" Then sCo = Left$(sCo, Len(sCo) - 1&)
If Right$(sCh, 1&) = "\" Then sCh = Left$(sCh, Len(sCh) - 1&)
If Left$(sCh, Len(sCo)) = sCo Then
    PathInPath = True
End If
End Function
'---------------------------------------------------------------------

'=====================================================================
'Starting the trace
'Now we're ready to get into the exciting stuff, starting the trace. The documentation
'was very scarce on this, and none of it applied to VB or similar languages, so it took
'a ton of reading of many sources, going over and over what documentation MS did provide,
'and even digging into the Windows source code to peak under the hood.
Public Function InitTrace() As Boolean
Dim hr As Long
Dim lErr As Long
Dim dmp(0 To 7) As Byte
Dim sdmp As String
Dim i As Long

'If we haven't already mapped our volumes to translate file names, do it now.
If bSetVM = False Then MapVolumes

'Prepare filters (your form must set the main strings before calling
'In a full app, you'd want to perform validation. Here, we'll trust input.
SetFilters

bInitRdDone = False

'Before Windows 8, there could only be one kernel logger running. You'd have to stop
'other apps, and other apps would stop yours. Newer systems support several simultaneous
'kernel logging sessions if we specify our own unique name and guid along with the
'EVENT_TRACE_SYSTEM_LOGGER_MODE flag.
If bUseNewLogMode Then
    SelectedGuid = VBKernelLoggerGuid
    SelectedName = gTraceName
Else
   SelectedGuid = SystemTraceControlGuid
   SelectedName = KERNEL_LOGGER_NAMEW
End If

'It's probably not neccessary in VB, but it's good habit to make sure
'structures that are sensitive to it are fully allocated.
ZeroMemory tTraceProps, LenB(tTraceProps)

'Now we have to fill in the main EVENT_TRACE_PROPERTIES structure. It's declared a the
'module level because ControlTrace calls need the same thing filled out. It's declared
'as a custom structure because of one of the issues you don't run into in any existing
'demos all in other languages... many ETW structures require 8-byte (QWORD) alignment,
'meaning the structure sizes have to be in multiples of 8 bytes. That's handled behind
'the scenes in other languages, but we need to do it manually in VB. The structure
'falls 4 bytes short, so we needed to add that padding before we allocated space for
'the Logger Name... which for some unknown and incredibly dumb reason, Windows will be
'copying into the memory after the structure even though you also have to pass it as
'it's own parameter in this and other functions. We include 4 bytes at the end
'because it's expecting a null-terminated string, so while NT Kernel Logger is 32 bytes,
'we need at least 2 more bytes. I added 4 to be safe, which aligns the total post-struct
'data to an 8 byte interval.
With tTraceProps.tProp
    .Wnode.Flags = WNODE_FLAG_TRACED_GUID
    .Wnode.ClientContext = 1&
    .Wnode.tGUID = SelectedGuid
    .Wnode.BufferSize = LenB(tTraceProps)
    .LogFileMode = EVENT_TRACE_REAL_TIME_MODE 'We're interested in doing real time monitoring, as opposed to processing a .etl file.
    If bUseNewLogMode Then
        .LogFileMode = .LogFileMode Or EVENT_TRACE_SYSTEM_LOGGER_MODE
    End If
    'The enable flags tell the system which classes of events we want to receive data for.
    .EnableFlags = EVENT_TRACE_FLAG_DISK_IO Or EVENT_TRACE_FLAG_DISK_FILE_IO Or _
                    EVENT_TRACE_FLAG_DISK_IO_INIT Or EVENT_TRACE_FLAG_NO_SYSCONFIG
    If (DiskIOExclusive = False) Or ((DiskIOExclusive = True) And (bSupDIOE = True)) Then
        .EnableFlags = .EnableFlags Or EVENT_TRACE_FLAG_FILE_IO Or EVENT_TRACE_FLAG_FILE_IO_INIT
    End If
    If bEnableCSwitch Then
        .EnableFlags = .EnableFlags Or EVENT_TRACE_FLAG_CSWITCH
    End If
    .FlushTimer = 1&
    .LogFileNameOffset = 0&
    .LoggerNameOffset = LenB(tTraceProps.tProp) + 4 'The logger name gets appended after the structure; but the system looks in 8 byte alignments,
                                                'so because of our padding, we tell it to start after an additional 4 bytes.
End With

'We're now ready to *begin* to start the trace. StartTrace is only 1/3rd of the way there...
hr = StartTraceW(gTraceHandle, StrPtr(SelectedName & vbNullChar), tTraceProps)
If hr = ERROR_ALREADY_EXISTS Then
    PostLog "StartTrace->Already exists, attempting to stop..."
    'If we're using the single logger option, another could be running, or if we crashed
    'without closing ours, it would still be running.
    hr = 0
    Call EndTrace(0&, gTraceHandle)
    Sleep 2000
    PostLog "StartTrace->Trying again..."
    hr = StartTraceW(gTraceHandle, StrPtr(SelectedName & vbNullChar), tTraceProps)
    'For some reason this doesn't work. But what this does do it make it so the app will work if you restart it.
End If
If hr <> ERROR_SUCCESS Then
    PostLog "StartTrace Error: " & GetErrorName(hr)
    Exit Function
End If

'We'll log the TraceHandle so we know got a valid one.
CopyMemory dmp(0), ByVal VarPtr(gTraceHandle), 8&
For i = 7 To 0 Step -1: sdmp = sdmp & Format$(Hex$(dmp(i)), "00") & ",": Next
PostLog "TraceHandle=0x" & sdmp: sdmp = ""
PostLog "StartTraceW->Success, LastErr=0x" & Hex$(lErr)

'We're now ready to proceed to step 2 of 3 in starting the trace, calling OpenTrace with a log file
'structure. Since we're doing a real-time trace, we dont need to worry about many items.
Dim tLogfile As EVENT_TRACE_LOGFILEW
ZeroMemory tLogfile, LenB(tLogfile)
tLogfile.LoggerName = StrPtr(SelectedName & vbNullChar)
tLogfile.Mode = PROCESS_TRACE_MODE_REAL_TIME Or PROCESS_TRACE_MODE_EVENT_RECORD 'Prior to Windows Vista, EventRecordCallback wasn't available.
tLogfile.EventCallback = FARPROC(AddressOf EventRecordCallback) 'Further down, you can see the prototype for EventCallback for the older version.
gSessionHandle = OpenTraceW(tLogfile)
lErr = Err.LastDllError

If gSessionHandle Then
    'If we got a handle back from OpenTrace, we're finally ready for step 3, after which we'll finally
    'begin receiving events: Calling ProcessTrace. But we run into a terrible design situation here.
    'ProcessTrace doesn't return until the trace is complete, which in a real time trace is forever
    'until we stop it. We don't want execution halted, so the normal way to do this is to call
    'ProcessTrace in a new thread. VB6 however, does not support multithread and normally crashes
    'if you attempt to call CreateThread. Some absolutely brilliant programmers have found workarounds
    'for this, and I settled on using a drop-in solution with no dependencies from fellow VBForums
    'member The trick.
    PostLog "OpenTrace successfully returned handle, spawning ProcessTrace thread..."
    Initialize
    hProcThread = vbCreateThread(0&, 0&, AddressOf ThreadProcTrace, ByVal 0&, 0&, hProcThreadId, False)
'    hProcThread = MakeThread(0&)
    If hProcThread Then InitTrace = True
    
    Dim hProc As Long
    hProc = OpenProcess(PROCESS_DUP_HANDLE, 1&, GetCurrentProcessId())
    If hProc Then
        hr = DuplicateHandle(hProc, hProcThread, hProc, hThreadWait, 0&, 0&, DUPLICATE_SAME_ACCESS)
    End If
    
Else
    PostLog "InitTrace->OpenTraceW failed, last error=" & GetErrorName(lErr)
End If
End Function

''We don't need this thread to do much... it's just here to call ProcessTrace then shut down when it returns.
Public Sub ThreadProcTrace(ByVal ThreadParam As Long)
Dim hr As Long
tidSelfProcEvt = GetCurrentThreadId()

If gSessionHandle Then
    hr = ProcessTrace(VarPtr(gSessionHandle), 1&, 0&, 0&)
    hr = CloseTrace(gSessionHandle)
    gSessionHandle = 0@
    gTraceHandle = 0@
End If
End Sub

'=====================================================================
'Controlling the trace
'If all went well, our callbacks are now receiving events. Here we'll put functions to
'control the trace as it runs, to flush the buffer or shut it down.

Public Sub EndTrace(ByVal hConsumer As Currency, ByVal hTrace As Currency)
Dim hr As Long
'Windows will have copied the logger name into the properties structure already, but
'nonetheless we have to supply it again...
PostLog "Sending ControlTrace(Stop)..."

'To shut down the trace we first send a stop message to the trace handle...
hr = ControlTraceW(hTrace, StrPtr(SelectedName & vbNullChar), tTraceProps, EVENT_TRACE_CONTROL_STOP)
If hr = ERROR_CTX_CLOSE_PENDING Then
    PostLog "ControlTraceW(Stop)->Success, stop pending."
ElseIf hr = ERROR_SUCCESS Then
    PostLog "ControlTraceW(Stop)->ERROR_SUCCESS"
Else
    PostLog "ControlTraceW(Stop)->Error: 0x" & Hex$(hr)
End If
PostLog CStr(tTraceProps.tProp.EventsLost) & " events lost during session."
End Sub

Public Sub FlushTrace(ByVal hTrace As Currency)
If hTrace Then
    Dim hr As Long
    hr = ControlTraceW(hTrace, StrPtr(SelectedName & vbNullChar), tTraceProps, EVENT_TRACE_CONTROL_FLUSH)
    
    If hr <> ERROR_SUCCESS Then
        PostLog "ControlTraceW(Flush):Error->" & GetErrorName(hr)
    Else
        PostLog "ControlTraceW(Flush)->Success"
    End If
Else
    PostLog "FlushTrace->No handle specified."
End If
End Sub

'This project isn't using it at the current time but you can get information about the buffer by
'setting the callback address in the OpenTrace structure.
Public Function BufferCallbackProc(pEventLogFile As EVENT_TRACE_LOGFILEW) As Long
BufferCallbackProc = 0&
End Function

'=====================================================================
'Processing events
'We're now finally at the part where we're receiving events from the logger.
'The events we receive here are based on the EnableFlags we filled out earlier, plus the default
'SystemConfig which we'd have to add a flag to not get; but we don't get many such messages so
'we might as well leave it in for some info verification in the future.
Public Sub EventRecordCallback(EventRecord As EVENT_RECORD)
If bEnableCSwitch Then
    If IsEqualGUID(EventRecord.EventHeader.ProviderId, ThreadGuid) Then
        If EventRecord.EventHeader.EventDescriptor.OpCode = ettCswitch Then
            Process_Thread_CSwitch EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, _
                                        EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version
        End If
    End If
End If

On Error GoTo EventRecordCallback_Err

If bPauseCol Then Exit Sub
If (bIgnoreSelf = True) And (EventRecord.EventHeader.ProcessID = pidSelf) Then Exit Sub
 
If bInitRdDone = False Then
    If bUseInitRd Then
        'If a file is already opened before the trace is started, we won't know about activity with it
        'unless it hits one of the non-readwrite events. A rundown lists all opened files with file objects,
        'so we can associate isolated read/write messages with opened files, but normally is only triggered
        'at the end of a trace, and then, only with the old logger method.
        'Here's an undocumented GUID and an undocumented trick to get one at the very start of our sessions:
        'The KernelRundownGuid represents the provider for the rundown, which is actually separate, and not
        'enabled by default on the new logger. When we enable it, we get a rundown. This works with both the
        'new and old logging method (with the old one, you'll get a 2nd on shutdown).
        bInitRdDone = True
        Dim enpm As ENABLE_TRACE_PARAMETERS
        enpm.Version = ENABLE_TRACE_PARAMETERS_VERSION_2
        Dim het As Long
        het = EnableTraceEx2(gTraceHandle, KernelRundownGuid, EVENT_CONTROL_CODE_ENABLE_PROVIDER, TRACE_LEVEL_NONE, &H10 / 10000, 0@, 0&, enpm)
        PostLog "EnableTraceEx2(Enable)=0x" & Hex$(het)
    End If
End If

'The list of events, their provider, and the corresponding code can be found (as of when this was
'written) here: https://docs.microsoft.com/en-us/windows/win32/etw/msnt-systemtrace
'The event numbers listed are the opcode here, equivalent to the uType in the old version.
'
'I left all the commented out codes posting the length in because it's important to make sure the
'sizes match; there's multiple versions of some of them, and if you're on an older (or possibly
'newer) version of Windows, they might be different, so we can quickly investigate.

Dim iCode As Byte
If IsEqualGUID(EventRecord.EventHeader.ProviderId, DiskIoGuid) Then
    iCode = EventRecord.EventHeader.EventDescriptor.OpCode
    
    'Some events use the same MOF structure and are processed similarly, so we group them together and separate
    'the codes for filtering and logging later.
    If (iCode = EVENT_TRACE_TYPE_IO_READ) Or (iCode = EVENT_TRACE_TYPE_IO_WRITE) Then
'        PostLog "DiskIo.ReadWrite, MofLength=" & EventRecord.UserDataLength
        Process_DiskIo_ReadWrite EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, _
                                    EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version, iCode
    End If
    
    If (iCode = EVENT_TRACE_TYPE_IO_READ_INIT) Or (iCode = EVENT_TRACE_TYPE_IO_WRITE_INIT) Then
        'PostLog "DiskIo.Init, MofLength=" & EventRecord.UserDataLength
        Process_DiskIo_Init EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, _
                                    EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version, iCode
    End If
    
    If (iCode = EVENT_TRACE_TYPE_IO_FLUSH) Then
        Process_DiskIo_Flush EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, _
                                    EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version, iCode
    End If
    
    If (iCode = EVENT_TRACE_TYPE_IO_FLUSH_INIT) Then
        Process_DiskIo_FlushInit EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, _
                                    EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version, iCode
    End If
    
    If (iCode = EVENT_TRACE_TYPE_IO_REDIRECTED_INIT) Then
        PostLog "DiskIo.Redirected, MofLength=" & EventRecord.UserDataLength & ", flags=" & GetEventHeaderFlagsStr(CLng(EventRecord.EventHeader.Flags))
        
    End If

ElseIf IsEqualGUID(EventRecord.EventHeader.ProviderId, FileIoGuid) Then
    iCode = EventRecord.EventHeader.EventDescriptor.OpCode
    Select Case iCode
        Case ettfioName
            If rdmax < 20 Then
                PostLog "FileIo.NameEvent, MofLength=" & EventRecord.UserDataLength
                rdmax = rdmax + 1
            End If
            '0 is the "Name event"... the MOF data consists simply of a FileObject and a name, and doesn't represent an action, just
            'creates the ability to associate other events where a filename isn't passed directly with the name by matching the object.
            Process_FileIo_Name EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, EventRecord.EventHeader.ThreadID

        Case ettfioCreate
    ''        PostLog "FileIo.CreateEvent32 v" & CStr(EventRecord.EventHeader.EventDescriptor.Version) & ", MofLength=" & EventRecord.UserDataLength
                Process_FileIo_Create32 EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version
            
        Case ettfioDelete
    '        PostLog "FileIo.DeleteEvent35 v" & CStr(EventRecord.EventHeader.EventDescriptor.Version) & ", MofLength=" & EventRecord.UserDataLength
                Process_FileIo_Delete35 EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version
        
        Case ettfioRundown
'            PostLog "FileIo_RundownEvent, MofLength=" & EventRecord.UserDataLength
                Process_FileIo_Rundown EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, _
                                        EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version, iCode
            
        Case ettfioCreate2
    '        PostLog "FileIo.CreateEvent64 v" & CStr(EventRecord.EventHeader.EventDescriptor.Version) & ", MofLength=" & EventRecord.UserDataLength
            Process_FileIo_Create64 EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version

        
        Case ettfioDirEnum, ettfioDirNotify
            If bEventDirEnum Then
                Process_FileIo_DirEnum EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version, iCode
            End If
        '    If iCode = 72 Then PostLog "FileIo.DirEnumEvent, MofLength=" & EventRecord.UserDataLength
        ''    If iCode = 77 Then PostLog "FileIo.DirNotifyEvent, MofLength=" & EventRecord.UserDataLength
            
        Case ettfioSetInfo, ettfioDelete2, ettfioRename, ettfioQueryInfo, ettfioFsctl  ''(Event Filters handled in processor)
            ' SetInfo, Delete, Rename, QueryInfo, 'FSCtlEvent
            Process_FileIo_InfoEvent EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version, iCode

        Case ettfioRead, ettfioWrite
            'PostLog "FileIo.ReadWriteEvent, MofLength=" & EventRecord.UserDataLength
            Process_FileIo_ReadWrite EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.EventDescriptor.Version, iCode, EventRecord.EventHeader.ProcessID, EventRecord.EventHeader.ThreadID

        Case ettfioCleanup, ettfioClose, ettfioFlush
            Process_FileIo_SimpleOp EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, _
                                    EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version, iCode
        
        Case ettfioOpEnd
'           If iCode = 76 Then PostLog "FileIo.OpEndEvent, MofLength=" & EventRecord.UserDataLength
            Process_FileIo_OpEnd EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, _
                                    EventRecord.EventHeader.ThreadID, EventRecord.EventHeader.EventDescriptor.Version, iCode
        
   'The following messages are undocumented, as is the MOF structure they use.
'        Case 37 To 40
'            If iCode = ettfioMapFileEvent Then PostLog "FileIo.MapFileEvent, MofLength=" & EventRecord.UserDataLength
'            If iCode = ettfioViewBaseEvent Then PostLog "FileIo.ViewBaseEvent, MofLength=" & EventRecord.UserDataLength
'            If iCode = ettfioMapFileDCStart Then PostLog "FileIo.MapFileDCStartEvent, MofLength=" & EventRecord.UserDataLength
'            If iCode = ettfioMapFileDCEnd Then PostLog "FileIo.MapFileDCEndEvent, MofLength=" & EventRecord.UserDataLength
            
        Case ettfioDletePath, ettfioRenamePath, ettfioSetLinkPath '(Event Filters handled in processor)
            'DletePath, RenamePath, SetLinkPath
            Process_FileIo_PathOp EventRecord.UserData, CLng(EventRecord.UserDataLength), EventRecord.EventHeader.ProcessID, EventRecord.EventHeader.ThreadID, iCode, EventRecord.EventHeader.EventDescriptor.Version
    
    End Select
End If

Exit Sub

EventRecordCallback_Err:
    PostLog "EventRecordCallback.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Sub Process_Thread_CSwitch(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte)
Dim tCW As Thread_CSwitch

'All we need is the new and old threadid, which is the 1st two members of the structure
'Copy only those for performance and as a bulwark against MS constantly fucking with this
'structure and refusing to document new versions.
CopyMemory tCW, ByVal ptr, 8&
If tCW.NewThreadId = tidSelfProcEvt Then pidCur = pidSelf: Exit Sub
Dim hThread As Long
hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tCW.NewThreadId)
pidCur = GetProcessIdOfThread(hThread)
CloseHandle hThread
If pidCur Then Exit Sub
Dim hTL As Long
hTL = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tCW.OldThreadId)
pidLast = GetProcessIdOfThread(hTL)
CloseHandle hTL

End Sub

Private Sub Process_DiskIo_FlushInit(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte, lCode As Byte)
'Not generally much to do with a flush right now... but we'll try to update -1 pids while we can
Dim tDIO As DiskIo_TypeGroup2_64
If (cb > LenB(tDIO)) Then
    PostLog "Process_DiskIo_FlushInit Error: Buffer too small, cb=" & cb
    Exit Sub
End If

Dim i As Long
Dim pFO As Currency
Dim hThread As Long
Dim lPid As Long

CopyMemory tDIO, ByVal ptr, cb

If nDIOR Then
    For i = 0& To UBound(DiskIoRecords)
        If DiskIoRecords(i).IRP = tDIO.IRP Then
            pFO = DiskIoRecords(i).FileObject
            Exit For
        End If
    Next i
End If

If pFO Then
    If tDIO.IssuingThreadId > 0& Then
        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tDIO.IssuingThreadId)
        lPid = GetProcessIdOfThread(hThread)
        CloseHandle hThread
        EnterCriticalSection oCS
        If nAcEv Then
            For i = 0 To UBound(ActivityLog)
                If ActivityLog(i).intFileObj = pFO Then
                    If ActivityLog(i).intProcId = -1 Then
                        ActivityUpdateProcess i, lPid
                        PostLog "DiskIo_FlushInit,pid(-1), UPDATEPROCNAME:" & ActivityLog(i).sProcess & "->thread=" & tDIO.IssuingThreadId & ",file=" & ActivityLog(i).sFile
                    End If
                End If
            Next i
        End If
        LeaveCriticalSection oCS
    End If
End If
End Sub

Private Sub Process_FileIo_Rundown(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte, lCode As Byte)
'Many operations make it impossible to find a pid besides -1 until this op.

On Error GoTo Process_FileIo_Rundown_Err

'If (PID = -1&) And (tid < 1&) Then Exit Sub
Dim tFIO As FileIo_Name64Ex
'If (cb > (8 + (MAX_PATH_DOS * 2))) Then
'    PostLog "Process_FileIo_Rundown Error: Buffer too small, cb=" & cb
'    Exit Sub
'End If
'
'CopyMemory tFIO, ByVal ptr, cb
Fill_FileIoName64 ptr, cb, tFIO


'If nAcEv Then
'    Dim i As Long
'    Dim hThread As Long
'    For i = 0& To UBound(ActivityLog)
'        If ActivityLog(i).intProcId = -1& Then
'            If (ActivityLog(i).intFileObj = tFIO.FileObject) Then
'                If (PID <> -1&) Or (tid > 0&) Then
'                    If rdmax < 20 Then
'                        If tFIO.FileObject Then
'                            PostLog "Rundown match for null pid " & ActivityLog(i).sFile
'                        Else
'                            PostLog "Rundown Match null obj"
'                        End If
'                        rdmax = rdmax + 1
'                    End If
'                    If PID <> -1& Then
'                        GetProcessInfoFromPID PID, ActivityLog(i).sProcess, ActivityLog(i).intProcPath, ActivityLog(i).iIcon
'                    ElseIf tid > 0& Then
'                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
'                        ActivityLog(i).intProcId = GetProcessIdOfThread(hThread)
'                        CloseHandle hThread
'                        GetProcessInfoFromPID ActivityLog(i).intProcId, ActivityLog(i).sProcess, ActivityLog(i).intProcPath, ActivityLog(i).iIcon
'                    End If
'                End If
'            End If
'        End If
'    Next
'End If

'Dim sNT As String
''sNT = WCHARtoStr(tFIO.FileName)
'SysReAllocStringLen VarPtr(sNT), VarPtr(tFIO.FileName(0&)), lstrlenW(ByVal (VarPtr(tFIO.FileName(0&))))

AppendFNR tFIO.FileName, tFIO.FileObject, pid, tid

If bEventNoRundown Then Exit Sub
AddActivity tFIO.FileName, pid, atRundown, lCode, tFIO.FileObject

Exit Sub

Process_FileIo_Rundown_Err:
    PostLog "Process_FileIo_Rundown.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Sub Process_FileIo_OpEnd(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte, lCode As Byte)

On Error GoTo Process_FileIo_OpEnd_Err

'If (pid = -1&) And (tid < 1&) Then Exit Sub
Dim tFIO As FileIo_OpEnd64
If (cb > LenB(tFIO)) Then
    PostLog "Process_FileIo_OpEnd Error: Buffer too small, cb=" & cb
    Exit Sub
End If

CopyMemory tFIO, ByVal ptr, cb

'First, link irp to fobj
Dim i As Long
Dim hThread As Long
Dim lIdx As Long
Dim FobjMatch As Currency

Dim frwpid As Long, diopid As Long
frwpid = -1&: diopid = -1&
lIdx = FIrpExists(tFIO.IrpPtr)
If lIdx > -1& Then
    frwpid = FileRWRecs(lIdx).ProcessID
    FobjMatch = FileRWRecs(lIdx).FileObject
End If

lIdx = GetDIOByIrp(tFIO.IrpPtr)
If lIdx > -1& Then
    diopid = DiskIoRecords(lIdx).IssuingProc
    FobjMatch = DiskIoRecords(lIdx).FileObject 'Superseding is fine; the same Irp will point to the same FileObject
End If

If (frwpid <> -1&) Or (diopid <> -1&) Or (pid <> -1&) Or (tid > 0&) Then
    EnterCriticalSection oCS
    If nAcEv Then
        For i = 0& To UBound(ActivityLog)
            If ActivityLog(i).intProcId = -1& Then
                If (ActivityLog(i).intFileObj = FobjMatch) Then
                    'If dbgmax < 20 Then
                        If FobjMatch Then
                            PostLog "EndOp match for null pid " & ActivityLog(i).sFile
                        Else
                            PostLog "EndOp Match null obj"
                        End If
                        'dbgmax = dbgmax + 1
                    'End If
                    If pid <> -1& Then
                        ActivityUpdateProcess i, pid
                    ElseIf tid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
                    ElseIf frwpid <> -1& Then
                        ActivityUpdateProcess i, frwpid
                    ElseIf diopid <> -1& Then
                        ActivityUpdateProcess i, diopid
                    End If
                End If
            End If
        Next
    End If
    LeaveCriticalSection oCS
    Exit Sub
    
End If


Exit Sub

Process_FileIo_OpEnd_Err:
    PostLog "Process_FileIo_OpEnd.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

 
Private Sub Process_FileIo_SimpleOp(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte, lCode As Byte)
'Many operations make it impossible to find a pid besides -1 until this op.

On Error GoTo Process_FileIo_SimpleOp_Err

Dim tFIO As FileIo_SimpleOp64
If (cb <> LenB(tFIO)) Then
    PostLog "Process_FileIo_SimpleOp Error: Buffer size mismatch, cb=" & cb
    Exit Sub
End If

CopyMemory tFIO, ByVal ptr, cb
Dim i As Long
Dim hThread As Long
Dim lIdx As Long
Dim diopid As Long: diopid = -1&
lIdx = GetDIOByIrp(tFIO.IrpPtr)
If lIdx > -1& Then
    If DiskIoRecords(lIdx).IssuingProc <> -1& Then
        diopid = DiskIoRecords(lIdx).IssuingProc
    End If
End If

If (pid <> -1&) Or (tid > 0&) Or (tFIO.ttid > 0&) Or (diopid <> -1&) Then
    Dim tpid As Long: tpid = -1&
    If tFIO.ttid > 0& Then
        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tFIO.ttid)
        tpid = GetProcessIdOfThread(hThread)
        CloseHandle hThread
    End If
    EnterCriticalSection oCS
    If nAcEv Then
        For i = 0& To UBound(ActivityLog)
            If ActivityLog(i).intProcId = -1& Then
                If (ActivityLog(i).intFileObj = tFIO.FileObject) Or (ActivityLog(i).intFileObj = tFIO.FileKey) Then
                    If dbgmax < 20 Then
                        If tFIO.FileObject Then
                            If tFIO.FileObject <> tFIO.FileKey Then
                                PostLog "SimpleOp FOBJMISMATCH; match for null pid " & ActivityLog(i).sFile
                            Else
                                PostLog "SimpleOp match for null pid " & ActivityLog(i).sFile
                            End If
                        Else
                            PostLog "SimpleOp Match null obj"
                            If tFIO.FileKey Then
                                PostLog "SimpleOp match for null pid " & ActivityLog(i).sFile
                            Else
                                PostLog "SimpleOp Match null obj"
                            End If
                        End If
                        dbgmax = dbgmax + 1
                    End If
                    If tpid <> -1& Then
                        ActivityUpdateProcess i, tpid
                    ElseIf pid <> -1& Then
                        ActivityUpdateProcess i, pid
                    ElseIf tid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
                    ElseIf diopid <> -1& Then
                        ActivityUpdateProcess i, diopid
                    End If
                End If
            End If
        Next
    End If
    LeaveCriticalSection oCS
End If

    
'    EnterCriticalSection oCS
'    If nAcEv Then
'        For i = 0& To UBound(ActivityLog)
'            If ActivityLog(i).intProcId = -1& Then
'                If (ActivityLog(i).intFileObj = DiskIoRecords(lIdx).FileObject) Then
'                    If (pid <> -1&) Or (tid > 0&) Or (DiskIoRecords(lIdx).IssuingProc <> -1&) Then
'                        'If dbgmax < 20 Then
'                            If DiskIoRecords(lIdx).FileObject Then
'                                PostLog "SimpleOp via DiskIo match for null pid " & ActivityLog(i).sFile
'                            Else
'                                PostLog "SimpleOp Match null obj"
'                            End If
'                            'dbgmax = dbgmax + 1
'                        'End If
'                        If DiskIoRecords(lIdx).IssuingProc <> -1& Then
'                            ActivityUpdateProcess i, DiskIoRecords(lIdx).IssuingProc
'                        ElseIf pid <> -1& Then
'                            ActivityUpdateProcess i, pid
'                        ElseIf tid > 0& Then
'                            hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
'                            ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
'                            CloseHandle hThread
'                        End If
'                    End If
'                End If
'            End If
'        Next
'    End If
'    LeaveCriticalSection oCS
'End If

Exit Sub

Process_FileIo_SimpleOp_Err:
    PostLog "Process_FileIo_SimpleOp.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Sub Process_DiskIo_Flush(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte, lCode As Byte)
'Not generally much to do with a flush right now... but we'll try to update -1 pids while we can

On Error GoTo Process_DiskIo_Flush_Err

Dim tDIO As DiskIo_TypeGroup3_64
If (cb > LenB(tDIO)) Then
    PostLog "Process_DiskIo_Flush Error: Buffer too small, cb=" & cb
    Exit Sub
End If

CopyMemory tDIO, ByVal ptr, cb
EnterCriticalSection oCS
If nAcEv Then
    Dim i As Long
    Dim hThread As Long
    Dim pFO As Currency
    If nDIOR Then
        For i = 0& To UBound(DiskIoRecords)
            If DiskIoRecords(i).IRP = tDIO.IRP Then
                pFO = DiskIoRecords(i).FileObject
                Exit For
            End If
        Next i
    End If
    If pFO Then
        For i = 0 To UBound(ActivityLog)
            If ActivityLog(i).intFileObj = pFO Then
                If ActivityLog(i).intProcId = -1& Then
                    If tDIO.IssuingThreadId > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tDIO.IssuingThreadId)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
                    ElseIf pid <> -1& Then
                        ActivityUpdateProcess i, pid
                    ElseIf tid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
                    End If
                    PostLog "DiskIo_Flush,pid(-1), UPDATEPROCNAME:" & ActivityLog(i).sProcess & "->thread=" & tDIO.IssuingThreadId & ",file=" & ActivityLog(i).sFile
                End If
            End If
        Next i
    End If
End If
LeaveCriticalSection oCS

Exit Sub

Process_DiskIo_Flush_Err:
    LeaveCriticalSection oCS
    PostLog "Process_DiskIo_Flush.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Sub Process_DiskIo_Init(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte, lCode As Byte)

On Error GoTo Process_DiskIo_Init_Err

Dim tDIOI As DiskIo_TypeGroup2_64
If (cb > LenB(tDIOI)) Then
    PostLog "Process_DiskIo_Init Error: Buffer too small, cb=" & cb
    Exit Sub
End If

CopyMemory tDIOI, ByVal ptr, cb

EnterCriticalSection oCS
If nAcEv Then
    Dim i As Long
    Dim hThread As Long
    Dim pFO As Currency
    If nDIOR Then
        For i = 0& To UBound(DiskIoRecords)
            If DiskIoRecords(i).IRP = tDIOI.IRP Then
                pFO = DiskIoRecords(i).FileObject
                Exit For
            End If
        Next i
    End If
    If pFO Then
        For i = 0 To UBound(ActivityLog)
            If ActivityLog(i).intFileObj = pFO Then
                If ActivityLog(i).intProcId = -1 Then
                    If tDIOI.IssuingThreadId > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tDIOI.IssuingThreadId)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
                    ElseIf pid <> -1& Then
                        ActivityUpdateProcess i, pid
                    ElseIf tid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
                    End If
                    PostLog "DiskIo_Init,pid(-1), UPDATEPROCNAME:" & ActivityLog(i).sProcess & "->thread=" & tDIOI.IssuingThreadId & ",file=" & ActivityLog(i).sFile
                End If
            End If
        Next i
    End If
End If
LeaveCriticalSection oCS

ReDim Preserve DiskIoRecords(nDIOR)
DiskIoRecords(nDIOR).IRP = tDIOI.IRP
DiskIoRecords(nDIOR).IssuingThread = tDIOI.IssuingThreadId
If tDIOI.IssuingThreadId Then
    hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tDIOI.IssuingThreadId)
    DiskIoRecords(nDIOR).IssuingProc = GetProcessIdOfThread(hThread)
    EnsurePidCached DiskIoRecords(nDIOR).IssuingProc
    CloseHandle hThread
End If
nDIOR = nDIOR + 1&
 

Exit Sub

Process_DiskIo_Init_Err:
    LeaveCriticalSection oCS
    PostLog "Process_DiskIo_Init.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Sub Process_DiskIo_ReadWrite(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte, lCode As Byte)

On Error GoTo Process_DiskIo_ReadWrite_Err

Dim tDIO As DiskIo_TypeGroup1_64
If (cb > LenB(tDIO)) Then
    PostLog "Process_DiskIo_ReadWrite Error: Buffer too small, cb=" & cb
    Exit Sub
End If
Dim hThread As Long
Dim lIdx As Long
Dim i As Long
Dim bMatch As Boolean
CopyMemory tDIO, ByVal ptr, cb



lIdx = GetDIOByIrp(tDIO.IRP)
If lIdx >= 0& Then
    DiskIoRecords(lIdx).FileObject = tDIO.FileObject
    If lCode = EVENT_TRACE_TYPE_IO_READ Then
        DiskIoRecords(lIdx).BytesRead = DiskIoRecords(lIdx).BytesRead + CCur(tDIO.TransferSize)
    Else
        DiskIoRecords(lIdx).BytesWritten = DiskIoRecords(lIdx).BytesWritten + CCur(tDIO.TransferSize)
    End If
    If DiskIoRecords(lIdx).IssuingThread = 0& Then
        DiskIoRecords(lIdx).IssuingThread = tDIO.IssuingThreadId
        If tDIO.IssuingThreadId Then
            hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tDIO.IssuingThreadId)
            DiskIoRecords(lIdx).IssuingProc = GetProcessIdOfThread(hThread)
            CloseHandle hThread
        End If
    End If
    GoTo findname
End If
lIdx = GetDIOByObj(tDIO.FileObject)
If lIdx >= 0& Then
    If DiskIoRecords(lIdx).IssuingThread = tDIO.IssuingThreadId Then 'only combine if same file+same thread
        DiskIoRecords(lIdx).IRP = tDIO.IRP
        If lCode = EVENT_TRACE_TYPE_IO_READ Then
            DiskIoRecords(lIdx).BytesRead = DiskIoRecords(lIdx).BytesRead + CCur(tDIO.TransferSize)
        Else
            DiskIoRecords(lIdx).BytesWritten = DiskIoRecords(lIdx).BytesWritten + CCur(tDIO.TransferSize)
        End If
        If DiskIoRecords(lIdx).IssuingThread = 0& Then
            DiskIoRecords(lIdx).IssuingThread = tDIO.IssuingThreadId
            If tDIO.IssuingThreadId Then
                hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tDIO.IssuingThreadId)
                DiskIoRecords(lIdx).IssuingProc = GetProcessIdOfThread(hThread)
                CloseHandle hThread
            End If
        End If
        GoTo findname
    End If
End If
ReDim Preserve DiskIoRecords(nDIOR)
DiskIoRecords(nDIOR).IRP = tDIO.IRP
DiskIoRecords(nDIOR).dwIrpFlags = tDIO.IrpFlags
DiskIoRecords(nDIOR).FileObject = tDIO.FileObject
DiskIoRecords(nDIOR).IssuingThread = tDIO.IssuingThreadId
DiskIoRecords(nDIOR).IssuingProc = -1&
If tDIO.IssuingThreadId Then
    hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tDIO.IssuingThreadId)
    DiskIoRecords(nDIOR).IssuingProc = GetProcessIdOfThread(hThread)
    EnsurePidCached DiskIoRecords(nDIOR).IssuingProc
    CloseHandle hThread
ElseIf tid Then
    hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
    DiskIoRecords(nDIOR).IssuingProc = GetProcessIdOfThread(hThread)
    EnsurePidCached DiskIoRecords(nDIOR).IssuingProc
    CloseHandle hThread
ElseIf pid <> -1& Then
    DiskIoRecords(nDIOR).IssuingProc = pid
End If
nDIOR = nDIOR + 1&
findname:
EnterCriticalSection oCS
If nAcEv Then
    For i = 0 To UBound(ActivityLog)
        If ActivityLog(i).iType <> atRundown Then
            If ActivityLog(i).intFileObj = tDIO.FileObject Then
                Dim tmpPid As Long
                If tDIO.IssuingThreadId > 0& Then
                    hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tDIO.IssuingThreadId)
                    tmpPid = GetProcessIdOfThread(hThread)
                    CloseHandle hThread
                ElseIf pid <> -1& Then
                    tmpPid = pid
                ElseIf tid > 0& Then
                    hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                    tmpPid = GetProcessIdOfThread(hThread)
                    CloseHandle hThread
                End If
                If ActivityLog(i).intProcId = -1& Then
                    ActivityUpdateProcess i, tmpPid
                    PostLog "DiskIo_ReadWrite pid(-1), UPDATEPROCNAME:" & ActivityLog(i).sProcess & "->thread=" & tDIO.IssuingThreadId & ",file=" & ActivityLog(i).sFile
                    If ActivityLog(i).iType = atFileAccess Then
                        'Update unattributed io we added. Don't worry about ids since we already tried filling it in.
                        ActivityUpdateRW tDIO.FileObject, tDIO.TransferSize, IIf(lCode = EVENT_TRACE_TYPE_IO_READ, EVENT_TRACE_TYPE_IO_READ, EVENT_TRACE_TYPE_IO_WRITE), True
                    End If
                    bMatch = True
                Else
                    'Only combine if same file *and* same process, since multiple processes can access the same file.
                    If ActivityLog(i).intProcId = tmpPid Then
                        If ActivityLog(i).iType = atFileAccess Then
                            'Update unattributed io we added. Don't worry about ids since we already tried filling it in.
                            ActivityUpdateRW tDIO.FileObject, tDIO.TransferSize, IIf(lCode = EVENT_TRACE_TYPE_IO_READ, EVENT_TRACE_TYPE_IO_READ, EVENT_TRACE_TYPE_IO_WRITE), True
                        End If
                        bMatch = True
                    End If
                End If
            End If
        End If
    Next i
End If
LeaveCriticalSection oCS
If bEventDiskIO = False Then Exit Sub
If bMatch = False Then
    'Unattributed IO. Try to match name and add it.
    If lIdx = -1& Then lIdx = nDIOR - 1& 'If no prior match we add from either the DiskIoRecord prev idx or the new one
    If nFNR Then
        For i = 0 To UBound(FileNameRecs)
            If FileNameRecs(i).FileObject = DiskIoRecords(lIdx).FileObject Then
                Dim sNote As String
                sNote = "Flags: "
                sNote = sNote & GetIrpFlagsStr(tDIO.IrpFlags)
                If (pid <> DiskIoRecords(lIdx).IssuingProc) And (pid <> -1&) Then
                    sNote = "(NeedProcCheck) " & sNote
                End If
                AddActivity FileNameRecs(i).FileName, DiskIoRecords(lIdx).IssuingProc, atFileAccess, lCode, DiskIoRecords(lIdx).FileObject, IIf(lCode = EVENT_TRACE_TYPE_IO_READ, DiskIoRecords(lIdx).BytesRead, 0&), IIf(lCode = EVENT_TRACE_TYPE_IO_WRITE, DiskIoRecords(lIdx).BytesWritten, 0&), sNote
                Exit For
            End If
        Next i
    End If
End If


Exit Sub

Process_DiskIo_ReadWrite_Err:
    PostLog "Process_DiskIo_ReadWrite.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Function GetDIOByObj(fobj As Currency) As Long
Dim i As Long

GetDIOByObj = -1&
If nDIOR Then
For i = 0& To UBound(DiskIoRecords)
    If DiskIoRecords(i).FileObject = fobj Then
        GetDIOByObj = i
        Exit Function
    End If
Next i
End If
 
End Function

Private Function GetDIOByIrp(fIrp As Currency) As Long
Dim i As Long

GetDIOByIrp = -1&
If nDIOR Then
For i = 0& To UBound(DiskIoRecords)
    If DiskIoRecords(i).IRP = fIrp Then
        GetDIOByIrp = i
        Exit Function
    End If
Next i
End If
End Function


Private Sub Process_FileIo_DirEnum(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte, lCode As Byte)

On Error GoTo Process_FileIo_DirEnum_Err

If DiskIOExclusive Then Exit Sub

Dim tNm As FileIo_DirEnum64Ex
Dim sNote As String
Dim sSrc As String
Dim sDir As String
Dim nMatch As Long
Dim i As Long
'dbg_AnalyzeMofStructDE ptr, cb, vz
Fill_FileIoDirEnum64 ptr, cb, tNm

'PostLog "DirEnum vz=" & CStr(vz) & "cb_raw=" & cb & ",cb_adj=" & CStr(cb - (LenB(tNm.FileName) + 1))
nMatch = -1&
If nFNR Then
    For i = 0& To UBound(FileNameRecs)
        If FileNameRecs(i).FileObject = tNm.FileKey Then
            sDir = FileNameRecs(i).FileName
            sSrc = "FNRKey"
            nMatch = i
            Exit For
        End If
    Next
End If
If nMatch = -1& Then
    If nFNR Then
    For i = 0& To UBound(FileNameRecs)
        If FileNameRecs(i).FileObject = tNm.FileObject Then
            sDir = FileNameRecs(i).FileName
            sSrc = "FNRObj"
            nMatch = i
            Exit For
        End If
    Next
    End If
End If
If nMatch = -1& Then
    If nFRW Then
        For i = 0& To UBound(FileRWRecs)
            If FileRWRecs(i).FileObject = tNm.FileKey Then
                sDir = FileRWRecs(i).PathName
                nMatch = i
                sSrc = "RwRecMatchKey"
                GoTo prc
                Exit For
            End If
        Next
    End If
End If
If nMatch = -1& Then
    If nFRW Then
        For i = 0& To UBound(FileRWRecs)
            If FileRWRecs(i).FileObject = tNm.FileObject Then
                sDir = FileRWRecs(i).PathName
                nMatch = i
                sSrc = "RwRecMatchObj"
                GoTo prc
                Exit For
            End If
        Next
    End If
End If
prc:
sNote = "Pattern=" & tNm.FileName & ", InfoClass=" & GetFileInfoClassStr(tNm.InfoClass)


If lCode = ettfioDirEnum Then
    Call AddActivity(sDir, pid, atDirEnum, ettfioDirEnum, tNm.FileKey, , , sNote, True)
Else
    Call AddActivity(sDir, pid, atDirNotify, ettfioDirNotify, tNm.FileKey, , , sNote, True)
End If

Exit Sub

Process_FileIo_DirEnum_Err:
    PostLog "Process_FileIo_DirEnum.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Sub Process_FileIo_PathOp(ptr As Long, cb As Long, pid As Long, tid As Long, lCode As Byte, vz As Byte)

On Error GoTo Process_FileIo_PathOp_Err
'dbg_AnalyzeMofStructPO ptr, cb, vz
Dim tNm As FileIo_PathOperation64Ex
Fill_FileIoPathOperation64 ptr, cb, tNm


Dim i As Long
Dim ndioi As Long, pidDio As Long
ndioi = GetDIOByIrp(tNm.IrpPtr)
If ndioi <> -1& Then
    pidDio = DiskIoRecords(ndioi).IssuingProc
Else
    pidDio = -1&
End If
If (pid <> -1&) Or (tid > 0&) Or (tNm.ttid > 0&) Or (pidDio <> -1&) Then
    EnterCriticalSection oCS
    If nAcEv Then
        Dim hThread As Long
        For i = 0& To UBound(ActivityLog)
            If ActivityLog(i).intProcId = -1& Then
                If (ActivityLog(i).intFileObj = tNm.FileObject) Or (ActivityLog(i).intFileObj = tNm.FileKey) Then
                    'If dbgmax < 20 Then
                        If tNm.FileObject Then
                            PostLog "PathOpEvent match for null pid " & ActivityLog(i).sFile
                        Else
                            If tNm.FileKey Then
                                PostLog "PathOpEvent match for null pid " & ActivityLog(i).sFile
                            Else
                                PostLog "PathOpEvent Match null obj"
                            End If
                        End If
                    '    dbgmax = dbgmax + 1
                    'End If
                    If pid <> -1& Then
                        ActivityUpdateProcess i, pid
                    ElseIf pidDio <> -1& Then
                        ActivityUpdateProcess i, pidDio
                    ElseIf tid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
                    ElseIf tNm.ttid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tNm.ttid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
                    End If
                End If
            End If
        Next
    End If
    LeaveCriticalSection oCS
End If

If DiskIOExclusive Then Exit Sub

Dim sMatch As String
Dim nMatch As Long
nMatch = -1&
If nFNR Then
    For i = 0& To UBound(FileNameRecs)
        If FileNameRecs(i).FileObject = tNm.FileKey Then
            sMatch = FileNameRecs(i).FileName
            nMatch = i
            Exit For
        End If
    Next
End If
If nMatch = -1& Then
    If nFNR Then
    For i = 0& To UBound(FileNameRecs)
        If FileNameRecs(i).FileObject = tNm.FileObject Then
            sMatch = FileNameRecs(i).FileName
            nMatch = i
            Exit For
        End If
    Next
    End If
End If

Dim sNote As String
If nMatch > -1& Then
    sNote = "Related file: " & ConvertNtPathToDosPath(sMatch)
End If

Select Case lCode
    Case ettfioDletePath: If bEventDelete Then Call AddActivity(tNm.FileName, pid, atDirDel, 79&, tNm.FileKey, , , sNote, True)
    Case ettfioRenamePath: If bEventRename Then Call AddActivity(tNm.FileName, pid, atDirRename, 80&, tNm.FileKey, , , sNote, True)
    Case ettfioSetLinkPath: If bEventSetInfo Then Call AddActivity(tNm.FileName, pid, atDirSetLink, 81&, tNm.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tNm.InfoClass) & ", " & sNote, True)
End Select

Exit Sub

Process_FileIo_PathOp_Err:
    PostLog "Process_FileIo_PathOp.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)
End Sub

Private Sub Process_FileIo_Name(ptr As Long, cb As Long, pid As Long, tid As Long)
Dim tNm As FileIo_Name64Ex
Fill_FileIoName64 ptr, cb, tNm
'This is for linking other events to file names, so we don't filter or generate an activity.
AppendFNR tNm.FileName, tNm.FileObject, pid, tid
End Sub

Private Sub AppendFNR(sName As String, fobj As Currency, pid As Long, tid As Long)
Dim i As Long
If nFNR Then
    For i = 0& To UBound(FileNameRecs)
        If FileNameRecs(i).FileObject = fobj Then Exit Sub
    Next
End If
ReDim Preserve FileNameRecs(nFNR)
FileNameRecs(nFNR).FileObject = fobj
FileNameRecs(nFNR).FileName = sName
FileNameRecs(nFNR).pid = pid
FileNameRecs(nFNR).tid = tid
nFNR = nFNR + 1
End Sub


Private Sub Process_FileIo_InfoEvent(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte, lCode As Byte)

On Error GoTo Process_FileIo_InfoEvent_Err

Dim tFIOD As FileIo_Info64
If cb > (LenB(tFIOD)) Then
    PostLog "Error: Insufficient buffer in Process_FileIo_InfoEvent, cb=" & cb
    Exit Sub
End If

CopyMemory ByVal VarPtr(tFIOD), ByVal ptr, cb
Dim i As Long
Dim ndioi As Long, pidDio As Long

If DiskIOExclusive Then GoTo scanpid

If nFNR Then
    
    For i = 0& To UBound(FileNameRecs)
        If FileNameRecs(i).FileObject = tFIOD.FileKey Then
            Select Case lCode
                Case ettfioSetInfo: If bEventSetInfo Then AddActivity FileNameRecs(i).FileName, IIf(pid <> -1&, pid, FileNameRecs(i).pid), atFileSetInfo, 69&, tFIOD.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tFIOD.InfoClass)
                Case ettfioDelete2: If bEventDelete Then AddActivity FileNameRecs(i).FileName, IIf(pid <> -1&, pid, FileNameRecs(i).pid), atFileDelete, 70&, tFIOD.FileKey
                Case ettfioRename: If bEventRename Then AddActivity FileNameRecs(i).FileName, IIf(pid <> -1&, pid, FileNameRecs(i).pid), atFileRename, 71&, tFIOD.FileKey
                Case ettfioQueryInfo: If bEventQuery Then AddActivity FileNameRecs(i).FileName, IIf(pid <> -1&, pid, FileNameRecs(i).pid), atFileQuery, 74&, tFIOD.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tFIOD.InfoClass)
                Case ettfioFsctl: If bEventFsctl Then AddActivity FileNameRecs(i).FileName, IIf(pid <> -1&, pid, FileNameRecs(i).pid), atFileFsctl, 75&, tFIOD.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tFIOD.InfoClass)
            End Select
            GoTo scanpid
        End If
    Next
End If
'According to MSDN we're supposed to be matching the name recs... but I've never gotten a name event???
If nFRW Then
    For i = 0& To UBound(FileRWRecs)
        If FileRWRecs(i).FileObject = tFIOD.FileKey Then
            Select Case lCode
                Case ettfioSetInfo: If bEventSetInfo Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileSetInfo, 69&, tFIOD.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tFIOD.InfoClass) & ";RwRecMatchKey"
                Case ettfioDelete2: If bEventDelete Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileDelete, 70&, tFIOD.FileKey, , , "RwRecMatchKey"
                Case ettfioRename: If bEventRename Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileRename, 71&, tFIOD.FileKey, , , "RwRecMatchKey"
                Case ettfioQueryInfo: If bEventQuery Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileQuery, 74&, tFIOD.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tFIOD.InfoClass) & ";RwRecMatchKey"
                Case ettfioFsctl: If bEventFsctl Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileFsctl, 75&, tFIOD.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tFIOD.InfoClass) & ";RwRecMatchKey"
            End Select
            GoTo scanpid
        End If
        If FileRWRecs(i).FileObject = tFIOD.FileObject Then
            Select Case lCode
                Case ettfioSetInfo: If bEventSetInfo Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileSetInfo, 69&, tFIOD.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tFIOD.InfoClass) & ";RwRecMatchObj"
                Case ettfioDelete2: If bEventDelete Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileDelete, 70&, tFIOD.FileKey, , , "RwRecMatchObj"
                Case ettfioRename: If bEventRename Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileRename, 71&, tFIOD.FileKey, , , "RwRecMatchObj"
                Case ettfioQueryInfo: If bEventQuery Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileQuery, 74&, tFIOD.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tFIOD.InfoClass) & ";RwRecMatchObj"
                Case ettfioFsctl: If bEventFsctl Then AddActivity FileRWRecs(i).PathName, IIf(pid <> -1&, pid, FileRWRecs(i).pid), atFileFsctl, 75&, tFIOD.FileKey, , , "InfoClass: " & GetFileInfoClassStr(tFIOD.InfoClass) & ";RwRecMatchObj"
            End Select
            GoTo scanpid
        End If
    Next
End If

scanpid:
ndioi = GetDIOByIrp(tFIOD.IrpPtr)
If ndioi <> -1& Then
    pidDio = DiskIoRecords(ndioi).IssuingProc
Else
    pidDio = -1&
End If
If (pid <> -1&) Or (tid > 0&) Or (tFIOD.ttid > 0&) Or (pidDio <> -1&) Then
    EnterCriticalSection oCS
    If nAcEv Then
        Dim hThread As Long
        For i = 0& To UBound(ActivityLog)
            If ActivityLog(i).intProcId = -1& Then
                If (ActivityLog(i).intFileObj = tFIOD.FileObject) Or (ActivityLog(i).intFileObj = tFIOD.FileKey) Then
                    'If dbgmax < 20 Then
                        If tFIOD.FileObject Then
                            PostLog "InfoEvent match for null pid " & ActivityLog(i).sFile
                        Else
                            If tFIOD.FileKey Then
                                PostLog "InfoEvent match for null pid " & ActivityLog(i).sFile
                            Else
                                PostLog "InfoEvent Match null obj"
                            End If
                        End If
                    '    dbgmax = dbgmax + 1
                    'End If
                    If pid <> -1& Then
                        ActivityUpdateProcess i, pid
                    ElseIf pidDio <> -1& Then
                        ActivityUpdateProcess i, pidDio
                    ElseIf tid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
'                    ElseIf tFIOD.ttid > 0& Then
'                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tFIOD.ttid)
'                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
'                        CloseHandle hThread
                    End If
                End If
            End If
        Next
    End If
    LeaveCriticalSection oCS
End If

Exit Sub

Process_FileIo_InfoEvent_Err:
    PostLog "Process_FileIo_InfoEvent.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Sub Process_FileIo_Delete35(ptr As Long, cb As Long, pid As Long, tid As Long, vz As Byte)

On Error GoTo Process_FileIo_Delete35_Err

Dim tFIOD As FileIo_Name64Ex
Fill_FileIoName64 ptr, cb, tFIOD

Dim sNote As String
Dim lIdx As Long
If pid = -1& Then
    Dim i As Long
    lIdx = GetDIOByObj(tFIOD.FileObject)
    If lIdx >= 0& Then
        pid = DiskIoRecords(lIdx).IssuingProc
        sNote = "dIoObjMatch" & sNote
    End If
End If

Dim hThread As Long
If (pid <> -1&) Or (tid > 0&) Then
    EnterCriticalSection oCS
    If nAcEv Then
        For i = 0& To UBound(ActivityLog)
            If ActivityLog(i).intProcId = -1& Then
                If (ActivityLog(i).intFileObj = tFIOD.FileObject) Then
                    'If dbgmax < 20 Then
                        If tFIOD.FileObject Then
                            PostLog "Del35Event match for null pid " & ActivityLog(i).sFile
                        End If
                    '    dbgmax = dbgmax + 1
                    'End If
                    If pid <> -1& Then
                        ActivityUpdateProcess i, pid
                    ElseIf tid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
                    End If
                End If
            End If
        Next
    End If
    LeaveCriticalSection oCS
End If

If (DiskIOExclusive = False) And (bEventDelete = False) Then Exit Sub

If AddActivity(tFIOD.FileName, pid, atFileDelete, 35&, tFIOD.FileObject, , , sNote) Then

End If


Exit Sub

Process_FileIo_Delete35_Err:
    PostLog "Process_FileIo_Delete35.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Sub Process_FileIo_ReadWrite(ptr As Long, cb As Long, vz As Byte, cd As Byte, pid As Long, tid As Long)

On Error GoTo Process_FileIo_ReadWrite_Err
Dim fio As FileIo_ReadWrite64
Dim fiov2 As FileIo_V2_ReadWrite64
Dim i As Long
Dim sNote As String
Dim hThread As Long
CopyMemory fio, ByVal ptr, cb
 
Dim ndioi As Long, pidDio As Long
ndioi = GetDIOByIrp(fio.IrpPtr)
If ndioi <> -1& Then
    pidDio = DiskIoRecords(ndioi).IssuingProc
Else
    pidDio = -1&
End If
If (pid <> -1&) Or (tid > 0&) Or (fio.ttid > 0&) Or (pidDio <> -1&) Then
    EnterCriticalSection oCS
    If nAcEv Then
        For i = 0& To UBound(ActivityLog)
            If ActivityLog(i).intProcId = -1& Then
                If (ActivityLog(i).intFileObj = fio.FileObject) Or (ActivityLog(i).intFileObj = fio.FileKey) Then
                    'If dbgmax < 20 Then
                        If fio.FileObject Then
'                            PostLog "FileRWEvent match for null pid[" & ActivityLog(i).sFile & "]"
                            
                        Else
                            If fio.FileKey Then
                                PostLog "FileRWEvent kmatch for null pid " & ActivityLog(i).sFile
                            Else
                                PostLog "FileRWEvent Match null obj"
                            End If
                        End If
                    '    dbgmax = dbgmax + 1
                    'End If
                    If pid <> -1& Then
                        ActivityUpdateProcess i, pid
                    ElseIf pidDio <> -1& Then
                        ActivityUpdateProcess i, pidDio
                    ElseIf tid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
'                    ElseIf fio.ttid > 0& Then
'                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, fio.ttid)
'                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
'                        CloseHandle hThread
                    End If
                End If
            End If
        Next
    End If
    LeaveCriticalSection oCS
End If

If DiskIOExclusive Then Exit Sub
'We still wanted process attribution even if we're not adding it, but now we'll check whether we need to go further:
If (bEventRead = False) And (cd = ettfioRead) Then Exit Sub
If (bEventWrite = False) And (cd = ettfioWrite) Then Exit Sub

Dim bFound As Boolean
EnterCriticalSection oCS
bFound = ActivityUpdateRW(fio.FileKey, fio.IoSize, cd, False)
LeaveCriticalSection oCS
If bFound = False Then
    EnterCriticalSection oCS
    bFound = ActivityUpdateRW(fio.FileObject, fio.IoSize, cd, False)
    LeaveCriticalSection oCS
End If
'If it wasn't found, we have an RW of a file opened before the trace started.
'If we can track down the filename, add it as a OpenFileRW event

If bFound = False Then
    If nFNR Then
        Dim nIdx As Long
        Dim fnpid As Long 'Final pid
        nIdx = -1&
        If nIdx = -1& Then
            For i = 0& To nFNR - 1&
                If FileNameRecs(i).FileObject = fio.FileKey Then
                    nIdx = i
                    Exit For
                End If
            Next i
        End If
        For i = 0& To nFNR - 1&
            If FileNameRecs(i).FileObject = fio.FileObject Then
                    PostLog "FileIo_ReadWrite No Key but Obj"
                nIdx = i
                Exit For
            End If
        Next i
        If nIdx >= 0& Then
            If pid <> -1& Then
                fnpid = pid
            ElseIf pidDio <> -1& Then
                fnpid = pidDio
            ElseIf tid <> -1& Then
                hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                fnpid = GetProcessIdOfThread(hThread)
                CloseHandle hThread
'            ElseIf fio.ttid > 0& Then
'                hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, fio.ttid)
'                fnpid = GetProcessIdOfThread(hThread)
'                CloseHandle hThread
            End If
            If fio.IoFlags Then sNote = "Flags: " & GetIrpFlagsStr(fio.IoFlags)
            Dim stmp As String
            stmp = "vz=" & CStr(vz) & ",cb=" & cb & ",io=" & fio.IoSize
            sNote = stmp & " " & sNote
            AddActivity FileNameRecs(nIdx).FileName, fnpid, atOpenFileRW, cd, fio.FileObject, IIf(cd = ettfioRead, fio.IoSize, 0&), IIf(cd = ettfioWrite, fio.IoSize, 0&), sNote
        End If
    End If
End If
Exit Sub
Process_FileIo_ReadWrite_Err:
    PostLog "Process_FileIo_ReadWrite.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)
End Sub

Private Sub Process_FileIo_Create32(ptr As Long, cb As Long, ByVal pid As Long, tid As Long, vz As Byte)
'Handles events providing a FileIo_Create MOF type.
If (DiskIOExclusive = False) And (bEventCreate = False) Then Exit Sub
On Error GoTo Process_FileIo_Create_Err

Dim tFIOC As FileIo_Name64Ex
Fill_FileIoName64 ptr, cb, tFIOC

EnterCriticalSection oCS
If nAcEv Then
    If (ActivityLog(nAcEv - 1&).intFileObj = tFIOC.FileObject) And (ActivityLog(nAcEv - 1&).iCode = 64) Then
        'This is just a Create(32) duplicate of a previous Create(64), ignore
        LeaveCriticalSection oCS
        Exit Sub
    End If
End If
LeaveCriticalSection oCS

Dim lIdx As Long
Dim sNote As String

EnterCriticalSection oCS
If nAcEv Then
    If (ActivityLog(nAcEv - 1&).sFile = ConvertNtPathToDosPath(tFIOC.FileName)) And (ActivityLog(nAcEv - 1&).iCode = 64) Then
        LeaveCriticalSection oCS
        PostLog "Create32 matched filename and code, but not file obj"
        Exit Sub
    End If
End If
LeaveCriticalSection oCS

Dim i As Long
If pid = -1& Then
    i = GetDIOByObj(tFIOC.FileObject)
    If i >= 0& Then
        pid = DiskIoRecords(i).IssuingProc
        sNote = "Used dioMatch for pid"
    End If
End If

        
If DiskIOExclusive Then
    Call AddActivity(tFIOC.FileName, pid, atFileAccess, 32&, tFIOC.FileObject, , , sNote)
Else
    lIdx = FObjExists(tFIOC.FileObject)
    If lIdx = -1& Then
        If AddActivity(tFIOC.FileName, pid, atFileCreate, 32&, tFIOC.FileObject, , , sNote) Then
            ReDim Preserve FileRWRecs(nFRW)
            With FileRWRecs(nFRW)
                .FileObject = tFIOC.FileObject
                If i >= 0& Then
                    .IRP = DiskIoRecords(i).IRP
                End If
                EnterCriticalSection oCS
                .PathName = ActivityLog(nAcEv - 1).sFile
                .ProcessName = ActivityLog(nAcEv - 1).sProcess
                .ProcessPath = ActivityLog(nAcEv - 1).intProcPath
                LeaveCriticalSection oCS
                .ProcessID = pid
            End With
            nFRW = nFRW + 1
         End If
    End If
End If
Exit Sub

Process_FileIo_Create_Err:
    PostLog "Process_FileIo_Create32.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)
End Sub

Private Sub Process_FileIo_Create64(ptr As Long, cb As Long, ByVal pid As Long, tid As Long, vz As Byte)
'Handles events providing a FileIo_Create MOF type.
On Error GoTo Process_FileIo_Create_Err
'dbg_AnalyzeMofStructCR ptr, cb, vz
Dim trc As Long
Dim tFIOC As FileIo_Create64Ex
Fill_FileIoCreate64 ptr, cb, tFIOC

Dim lIdx As Long
Dim i As Long


If pid = -1& Then
    If tFIOC.ttid > 0& Then
        Dim hThread As Long
        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tFIOC.ttid)
        pid = GetProcessIdOfThread(hThread)
        CloseHandle hThread
    Else
        lIdx = GetDIOByObj(tFIOC.FileObject)
        If lIdx >= 0& Then
            pid = DiskIoRecords(lIdx).IssuingProc
        Else
            lIdx = GetDIOByIrp(tFIOC.IrpPtr)
            If lIdx >= 0& Then
                pid = DiskIoRecords(lIdx).IssuingProc
            End If
        End If
    End If
End If

If (pid <> -1&) Or (tid > 0&) Or (tFIOC.ttid > 0&) Then
    EnterCriticalSection oCS
    If nAcEv Then
        For i = 0& To UBound(ActivityLog)
            If ActivityLog(i).intProcId = -1& Then
                If (ActivityLog(i).intFileObj = tFIOC.FileObject) Then
                    'If dbgmax < 20 Then
                        If tFIOC.FileObject Then
                            PostLog "Create64 match for null pid " & ActivityLog(i).sFile
                        End If
                    '    dbgmax = dbgmax + 1
                    'End If
                    If pid <> -1& Then
                        ActivityUpdateProcess i, pid
                    ElseIf tid > 0& Then
                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tid)
                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
                        CloseHandle hThread
'                    ElseIf tFIOC.ttid > 0& Then
'                        hThread = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, 0&, tFIOC.ttid)
'                        ActivityUpdateProcess i, GetProcessIdOfThread(hThread)
'                        CloseHandle hThread
                    End If
                End If
            End If
        Next
    End If
    LeaveCriticalSection oCS
End If

If DiskIOExclusive Or (bEventCreate = False) Then Exit Sub

Dim sNote As String
sNote = "ShareMode=" & GetShareStr(CInt(tFIOC.ShareAccess)) & ",CreateOpts=" & GetCreateOptsStr(tFIOC.CreateOptions)

If AddActivity(tFIOC.OpenPath, pid, atFileCreate, 64, tFIOC.FileObject, , , sNote) Then
    ReDim Preserve FileRWRecs(nFRW)
    With FileRWRecs(nFRW)
        .FileObject = tFIOC.FileObject
        .IRP = tFIOC.IrpPtr
        EnterCriticalSection oCS
        .PathName = ActivityLog(nAcEv - 1).sFile
        .ProcessName = ActivityLog(nAcEv - 1).sProcess
        .ProcessPath = ActivityLog(nAcEv - 1).intProcPath
        LeaveCriticalSection oCS
    End With
    nFRW = nFRW + 1&
End If

Exit Sub

Process_FileIo_Create_Err:
    PostLog "Process_FileIo_Create64.Error(Trace=" & trc & ")->" & Err.Description & ", 0x" & Hex$(Err.Number)

End Sub

Private Function FObjExists(key As Currency) As Long
FObjExists = -1&
If nFRW Then
    Dim i As Long
    For i = 0& To UBound(FileRWRecs)
        If FileRWRecs(i).FileObject = key Then
            FObjExists = i
            Exit Function
        End If
    Next i
End If
End Function
Private Function FIrpExists(key As Currency) As Long
FIrpExists = -1&
If nFRW Then
    Dim i As Long
    For i = 0& To UBound(FileRWRecs)
        If FileRWRecs(i).IRP = key Then
            FIrpExists = i
            Exit Function
        End If
    Next i
End If
End Function

Public Function AddActivity(ByVal sPath As String, ByVal pid As Long, ByVal nEvent As ActivityType, ByVal OpCode As Byte, FileObj As Currency, Optional lRead As Long = 0&, Optional lWrite As Long = 0&, Optional sMisc As String = "", Optional bDir As Boolean = False, Optional bFileResolved As Boolean = False) As Boolean

On Error GoTo AddActivity_Err
If nEvent = atRundown Then
    EnterCriticalSection oCS
    ReDim Preserve ActivityLog(nAcEv)
    ActivityLog(nAcEv).sProcess = sRdProc
'    ActivityLog(nAcEv).intProcPath = sProcPath
    ActivityLog(nAcEv).iIcon = 2
    ActivityLog(nAcEv).iType = nEvent
    ActivityLog(nAcEv).iCode = OpCode
    ActivityLog(nAcEv).sFile = ConvertNtPathToDosPath(sPath)
    ActivityLog(nAcEv).sMisc = sMisc
    ActivityLog(nAcEv).intListIdx = nAcEv
    ActivityLog(nAcEv).intProcId = pid
    ActivityLog(nAcEv).intFileObj = FileObj
    LeaveCriticalSection oCS
    nAcEv = nAcEv + 1
    Exit Function
End If

Dim sProc As String
Dim sProcPath As String
Dim nIcon As Long
Dim trc As Long 'debug trace
Dim sFile As String
Dim bCS As Boolean
If pid = -1& Then
    If bEnableCSwitch Then
        pid = pidCur
        bCS = True
    End If
End If
GetProcessInfoFromPID pid, sProc, sProcPath, nIcon
trc = 1&
If ItemIncluded(sProc, True, pid) = False Then
'   PostLog "AddActivity->Filtered based on process " & sProc
    Exit Function
End If
trc = 2&
 
If bFileResolved Then
    sFile = sPath
Else
    sFile = ConvertNtPathToDosPath(sPath)
End If
trc = 3&
If ItemIncluded(sFile, False) Then
    Dim dtStart As SYSTEMTIME
    GetLocalTime dtStart
    EnterCriticalSection oCS
    If bMergeSameFile Then
        If (OpCode = 10) Or (OpCode = 11) Or (OpCode = ettfioCreate) Or (OpCode = ettfioDelete) Or (OpCode = ettfioRead) Or _
             (OpCode = ettfioWrite) Or (OpCode = ettfioCreate) Or (OpCode = ettfioCreate2) Then
             Dim lIdx As Long
             lIdx = ActivityFindSame(sFile, pid, IIf(bMergeSameCode, OpCode, 0&))
             If lIdx >= 0& Then
                ActivityLog(lIdx).dtMod = dtStart
                ActivityLog(lIdx).cRead = ActivityLog(lIdx).cRead + CCur(lRead)
                ActivityLog(lIdx).cWrite = ActivityLog(lIdx).cWrite + CCur(lWrite)
                If (OpCode = ettfioCreate) Or (OpCode = ettfioCreate2) Then
                    ActivityLog(lIdx).OpenCount = ActivityLog(lIdx).OpenCount + 1&
                End If
                If (OpCode = ettfioDelete) Then
                    ActivityLog(lIdx).DeleteCount = ActivityLog(lIdx).DeleteCount + 1&
                End If
                LeaveCriticalSection oCS
                Exit Function
            End If
        End If
    End If
                
    trc = 4&
    ReDim Preserve ActivityLog(nAcEv)
    trc = 5&
    If bCS Then
        ActivityLog(nAcEv).sProcess = sProc & "*"
        If pid Then
            ActivityLog(nAcEv).sMisc = sMisc
        Else
            Dim sProcL As String
            Dim sProcPathL As String
            Dim nIconL As Long
            GetProcessInfoFromPID pidLast, sProcL, sProcPathL, nIconL
            sMisc = "LastProc=" & sProcL & "|" & sMisc
            ActivityLog(nAcEv).sMisc = sMisc
        End If
    Else
        ActivityLog(nAcEv).sProcess = sProc
        ActivityLog(nAcEv).sMisc = sMisc
    End If
    ActivityLog(nAcEv).iIcon = nIcon
    ActivityLog(nAcEv).iType = nEvent
    ActivityLog(nAcEv).iCode = CLng(OpCode)
    ActivityLog(nAcEv).sFile = sFile
    ActivityLog(nAcEv).dtStart = dtStart
    ActivityLog(nAcEv).cRead = CCur(lRead)
    ActivityLog(nAcEv).cWrite = CCur(lWrite)
    If (OpCode = ettfioCreate) Or (OpCode = ettfioCreate2) Then
        ActivityLog(nAcEv).OpenCount = 1&
    End If
    If (OpCode = ettfioDelete) Then
        ActivityLog(nAcEv).DeleteCount = 1&
    End If
    ActivityLog(nAcEv).intProcPath = sProcPath
    ActivityLog(nAcEv).intListIdx = nAcEv
    ActivityLog(nAcEv).intProcId = pid
    ActivityLog(nAcEv).intFileObj = FileObj
    trc = 6&
    nAcEv = nAcEv + 1
    LeaveCriticalSection oCS
    AddActivity = True
Else
'    PostLog "AddActivity->Filtered based on path " & sFile

End If

Exit Function

AddActivity_Err:
LeaveCriticalSection oCS
PostLog "AddActivity.Error->" & Err.Description & ", 0x" & Hex$(Err.Number) & ";pos=" & trc & ",sProc=" & sProc & ",code=" & OpCode & ",ct=" & nAcEv & _
                    ",File=" & sFile & ",note=" & sMisc

End Function

'**************************
'WARNING: Unlike AddActivity, it is the callers responsibility to enter the oCS critical section
'         before calling the following 3 functions.

Private Function ActivityFindSame(sFile As String, lPid As Long, ByVal OpCode As Byte) As Long
'Normally, when an operation completes, the FILE_OBJECT is released, so even if the same process accesses
'the same file again, it will be recorded as a new activity. As an optional feature, we can have a single
'event for all accesses of the same file by the same process.
Dim i As Long
ActivityFindSame = -1&
 
If nAcEv Then
    For i = 0& To (nAcEv - 1&)
        If ActivityLog(i).intProcId = lPid Then
            If ActivityLog(i).sFile = sFile Then
                If OpCode Then
                    If ActivityLog(i).iCode = OpCode Then
                        ActivityFindSame = i
                        Exit Function
                    ElseIf ((ActivityLog(i).iCode = EVENT_TRACE_TYPE_IO_READ) And (OpCode = EVENT_TRACE_TYPE_IO_WRITE)) Or ((ActivityLog(i).iCode = ettfioRead) And (OpCode = ettfioWrite)) Then
                        ActivityFindSame = i
                        Exit Function
                    ElseIf ((ActivityLog(i).iCode = EVENT_TRACE_TYPE_IO_WRITE) And (OpCode = EVENT_TRACE_TYPE_IO_READ)) Or ((ActivityLog(i).iCode = ettfioWrite) And (OpCode = ettfioRead)) Then
                        ActivityFindSame = i
                        Exit Function
                    End If
                Else
                    ActivityFindSame = i
                    Exit Function
                End If
            End If
        End If
    Next i
End If
End Function

Private Sub ActivityUpdateProcess(idx As Long, pid As Long)
Dim sProc As String, sPath As String
Dim nIcon As Long
GetProcessInfoFromPID pid, sProc, sPath, nIcon
ActivityLog(idx).intProcId = pid
ActivityLog(idx).sProcess = sProc
ActivityLog(idx).intProcPath = sPath
ActivityLog(idx).iIcon = nIcon
End Sub

Private Function ActivityUpdateRW(fobj As Currency, lAdd As Long, iWhich As Byte, bIsDisk As Boolean) As Boolean

On Error GoTo ActivityUpdateRW_Err

Dim i As Long
For i = 0 To UBound(ActivityLog)
  If ActivityLog(i).iType <> atRundown Then
    If ActivityLog(i).intFileObj = fobj Then
        Dim dtMod As SYSTEMTIME
        If bIsDisk Then
            If ActivityLog(i).iType = atFileAccess Then
                GetLocalTime dtMod
                If iWhich = EVENT_TRACE_TYPE_IO_READ Then
                    ActivityLog(i).cRead = ActivityLog(i).cRead + CCur(lAdd)
                    ActivityLog(i).dtMod = dtMod
                Else
                    ActivityLog(i).cWrite = ActivityLog(i).cWrite + CCur(lAdd)
                    ActivityLog(i).dtMod = dtMod
                End If
                ActivityUpdateRW = True
                Exit Function
            End If
        Else
            GetLocalTime dtMod
            If iWhich = EVENT_TRACE_TYPE_IO_READ Then
                ActivityLog(i).cRead = ActivityLog(i).cRead + CCur(lAdd)
                ActivityLog(i).dtMod = dtMod
            Else
                ActivityLog(i).cWrite = ActivityLog(i).cWrite + CCur(lAdd)
                ActivityLog(i).dtMod = dtMod
            End If
            ActivityUpdateRW = True
            Exit Function
        End If
    End If
  End If
Next
Exit Function

ActivityUpdateRW_Err:
    PostLog "ActivityUpdateRW.Error->" & Err.Description & ", 0x" & Hex$(Err.Number)
End Function

Public Function DoEndRundown() As Long
Dim i As Long, j As Long
Dim iNm As Long
Dim bMatch As Boolean

If (nDIOR > 0&) And (nAcEv > 0&) Then
    For i = 0 To UBound(DiskIoRecords)
        bMatch = False
        For j = 0 To UBound(ActivityLog)
            If DiskIoRecords(i).FileObject = ActivityLog(j).intFileObj Then
                bMatch = True
                Exit For
            End If
        Next j
        If bMatch = False Then
            iNm = FindFNR(DiskIoRecords(i).FileObject)
            If iNm > -1& Then
                AddActivity FileNameRecs(i).FileName, DiskIoRecords(i).IssuingProc, atFileAccess, 67, DiskIoRecords(i).FileObject, CLng(DiskIoRecords(i).BytesRead), _
                    CLng(DiskIoRecords(i).BytesWritten), "Post-rundown lookup. Flags=" & GetIrpFlagsStr(DiskIoRecords(i).dwIrpFlags)
            End If
        End If
    Next i
End If

End Function

Public Function FindFNR(fobj As Currency) As Long
Dim i As Long
FindFNR = -1&
If nFNR Then
    For i = 0& To UBound(FileNameRecs)
        If FileNameRecs(i).FileObject = fobj Then
            FindFNR = i
            Exit Function
        End If
    Next i
End If
        
End Function



'Alterntative Callback Implementation Prototypes
'You can also use these if you're trying to implement this on older systems.
'The EventRecordCallback method was unavailable on Windows XP.
'But be aware, many event types won't be either.
Public Function EventCallback(pEvent As EVENT_TRACE) As Long

End Function

Public Function FileIoEventCallback(pEvent As EVENT_TRACE) As Long

End Function

Public Function DiskIoEventCallback(pEvent As EVENT_TRACE) As Long
 
End Function

Public Function SysConfEventCallback(pEvent As EVENT_TRACE) As Long
 
End Function

'Alterntative

'hr = SetTraceCallback(SystemConfigGuid, AddressOf SysConfEventCallback)
'If hr <> ERROR_SUCCESS Then
'    PostLog "SetTraceCallback(SystemConfigGuid)->Error: " & GetErrorName(hr)
'End If
'hr = SetTraceCallback(FileIoGuid, AddressOf FileIoEventCallback)
'If hr <> ERROR_SUCCESS Then
'    PostLog "SetTraceCallback(FileIoGuid)->Error: " & GetErrorName(hr)
'End If
'hr = SetTraceCallback(DiskIoGuid, AddressOf DiskIoEventCallback)
'If hr <> ERROR_SUCCESS Then
'    PostLog "SetTraceCallback(DiskIoGuid)->Error: " & GetErrorName(hr)
'End If
'PostLog "SetTraceCallbacks->Success"


Public Function GetErrorName(LastDllError As Long) As String
Dim sErr As String
Dim lRet As Long
sErr = Space$(1024)
lRet = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM Or FORMAT_MESSAGE_IGNORE_INSERTS, _
            ByVal 0&, LastDllError, 0&, ByVal StrPtr(sErr), Len(sErr), ByVal 0&)
If lRet Then
    GetErrorName = Left$(sErr, lRet)
    If InStr(GetErrorName, vbCrLf) > 0 Then
        GetErrorName = Left$(GetErrorName, InStr(GetErrorName, vbCrLf) - 1)
    End If
End If
GetErrorName = "0x" & Hex$(LastDllError) & " - " & GetErrorName
End Function


Public Function GetCreateOptsStr(lVal As Long) As String
Dim sRet As String
If lVal Then
 If (lVal And FILE_SUPERSEDE) = FILE_SUPERSEDE Then sRet = sRet & "FILE_SUPERSEDE Or "
 If (lVal And FILE_OPEN) = FILE_OPEN Then sRet = sRet & "FILE_OPEN Or "
 If (lVal And FILE_CREATE) = FILE_CREATE Then sRet = sRet & "FILE_CREATE Or "
 If (lVal And FILE_OPEN_IF) = FILE_OPEN_IF Then sRet = sRet & "FILE_OPEN_IF Or "
 If (lVal And FILE_OVERWRITE) = FILE_OVERWRITE Then sRet = sRet & "FILE_OVERWRITE Or "
 If (lVal And FILE_OVERWRITE_IF) = FILE_OVERWRITE_IF Then sRet = sRet & "FILE_OVERWRITE_IF Or "
 If (lVal And FILE_MAXIMUM_DISPOSITION) = FILE_MAXIMUM_DISPOSITION Then sRet = sRet & "FILE_MAXIMUM_DISPOSITION Or "
 If (lVal And FILE_DIRECTORY_FILE) = FILE_DIRECTORY_FILE Then sRet = sRet & "FILE_DIRECTORY_FILE Or "
 If (lVal And FILE_WRITE_THROUGH) = FILE_WRITE_THROUGH Then sRet = sRet & "FILE_WRITE_THROUGH Or "
 If (lVal And FILE_SEQUENTIAL_ONLY) = FILE_SEQUENTIAL_ONLY Then sRet = sRet & "FILE_SEQUENTIAL_ONLY Or "
 If (lVal And FILE_NO_INTERMEDIATE_BUFFERING) = FILE_NO_INTERMEDIATE_BUFFERING Then sRet = sRet & "FILE_NO_INTERMEDIATE_BUFFERING Or "
 If (lVal And FILE_SYNCHRONOUS_IO_ALERT) = FILE_SYNCHRONOUS_IO_ALERT Then sRet = sRet & "FILE_SYNCHRONOUS_IO_ALERT Or "
 If (lVal And FILE_SYNCHRONOUS_IO_NONALERT) = FILE_SYNCHRONOUS_IO_NONALERT Then sRet = sRet & "FILE_SYNCHRONOUS_IO_NONALERT Or "
 If (lVal And FILE_NON_DIRECTORY_FILE) = FILE_NON_DIRECTORY_FILE Then sRet = sRet & "FILE_NON_DIRECTORY_FILE Or "
 If (lVal And FILE_CREATE_TREE_CONNECTION) = FILE_CREATE_TREE_CONNECTION Then sRet = sRet & "FILE_CREATE_TREE_CONNECTION Or "
 If (lVal And FILE_COMPLETE_IF_OPLOCKED) = FILE_COMPLETE_IF_OPLOCKED Then sRet = sRet & "FILE_COMPLETE_IF_OPLOCKED Or "
 If (lVal And FILE_NO_EA_KNOWLEDGE) = FILE_NO_EA_KNOWLEDGE Then sRet = sRet & "FILE_NO_EA_KNOWLEDGE Or "
 If (lVal And FILE_OPEN_FOR_RECOVERY) = FILE_OPEN_FOR_RECOVERY Then sRet = sRet & "FILE_OPEN_FOR_RECOVERY Or "
 If (lVal And FILE_RANDOM_ACCESS) = FILE_RANDOM_ACCESS Then sRet = sRet & "FILE_RANDOM_ACCESS Or "
 If (lVal And FILE_DELETE_ON_CLOSE) = FILE_DELETE_ON_CLOSE Then sRet = sRet & "FILE_DELETE_ON_CLOSE Or "
 If (lVal And FILE_OPEN_BY_FILE_ID) = FILE_OPEN_BY_FILE_ID Then sRet = sRet & "FILE_OPEN_BY_FILE_ID Or "
 If (lVal And FILE_OPEN_FOR_BACKUP_INTENT) = FILE_OPEN_FOR_BACKUP_INTENT Then sRet = sRet & "FILE_OPEN_FOR_BACKUP_INTENT Or "
 If (lVal And FILE_NO_COMPRESSION) = FILE_NO_COMPRESSION Then sRet = sRet & "FILE_NO_COMPRESSION Or "
 If (lVal And FILE_OPEN_REQUIRING_OPLOCK) = FILE_OPEN_REQUIRING_OPLOCK Then sRet = sRet & "FILE_OPEN_REQUIRING_OPLOCK Or "
 If (lVal And FILE_DISALLOW_EXCLUSIVE) = FILE_DISALLOW_EXCLUSIVE Then sRet = sRet & "FILE_DISALLOW_EXCLUSIVE Or "
 If (lVal And FILE_SESSION_AWARE) = FILE_SESSION_AWARE Then sRet = sRet & "FILE_SESSION_AWARE Or "
 If (lVal And FILE_RESERVE_OPFILTER) = FILE_RESERVE_OPFILTER Then sRet = sRet & "FILE_RESERVE_OPFILTER Or "
 If (lVal And FILE_OPEN_REPARSE_POINT) = FILE_OPEN_REPARSE_POINT Then sRet = sRet & "FILE_OPEN_REPARSE_POINT Or "
 If (lVal And FILE_OPEN_NO_RECALL) = FILE_OPEN_NO_RECALL Then sRet = sRet & "FILE_OPEN_NO_RECALL Or "
 If (lVal And FILE_OPEN_FOR_FREE_SPACE_QUERY) = FILE_OPEN_FOR_FREE_SPACE_QUERY Then sRet = sRet & "FILE_OPEN_FOR_FREE_SPACE_QUERY Or "
 If sRet = "" Then sRet = "(unknown)"
 If Right$(sRet, 4&) = " Or " Then
     sRet = Left$(sRet, Len(sRet) - 4)
 End If
Else
 sRet = "(none)"
End If
GetCreateOptsStr = sRet
End Function

Public Function GetFILE_ATTRIBUTESStr(lVal As Long) As String
Dim sRet As String
 If (lVal And INVALID_FILE_ATTRIBUTES) = INVALID_FILE_ATTRIBUTES Then sRet = sRet & "INVALID_FILE_ATTRIBUTES Or "
 If (lVal And FILE_ATTRIBUTE_READONLY) = FILE_ATTRIBUTE_READONLY Then sRet = sRet & "FILE_ATTRIBUTE_READONLY Or "
 If (lVal And FILE_ATTRIBUTE_HIDDEN) = FILE_ATTRIBUTE_HIDDEN Then sRet = sRet & "FILE_ATTRIBUTE_HIDDEN Or "
 If (lVal And FILE_ATTRIBUTE_SYSTEM) = FILE_ATTRIBUTE_SYSTEM Then sRet = sRet & "FILE_ATTRIBUTE_SYSTEM Or "
 If (lVal And FILE_ATTRIBUTE_ARCHIVE) = FILE_ATTRIBUTE_ARCHIVE Then sRet = sRet & "FILE_ATTRIBUTE_ARCHIVE Or "
 If (lVal And FILE_ATTRIBUTE_TEMPORARY) = FILE_ATTRIBUTE_TEMPORARY Then sRet = sRet & "FILE_ATTRIBUTE_TEMPORARY Or "
 If (lVal And FILE_ATTRIBUTE_OFFLINE) = FILE_ATTRIBUTE_OFFLINE Then sRet = sRet & "FILE_ATTRIBUTE_OFFLINE Or "
 If (lVal And FILE_ATTRIBUTE_NOT_CONTENT_INDEXED) = FILE_ATTRIBUTE_NOT_CONTENT_INDEXED Then sRet = sRet & "FILE_ATTRIBUTE_NOT_CONTENT_INDEXED Or "
 If (lVal And FILE_ATTRIBUTE_DIRECTORY) = FILE_ATTRIBUTE_DIRECTORY Then sRet = sRet & "FILE_ATTRIBUTE_DIRECTORY Or "
 If (lVal And FILE_ATTRIBUTE_DEVICE) = FILE_ATTRIBUTE_DEVICE Then sRet = sRet & "FILE_ATTRIBUTE_DEVICE Or "
 If (lVal And FILE_ATTRIBUTE_NORMAL) = FILE_ATTRIBUTE_NORMAL Then sRet = sRet & "FILE_ATTRIBUTE_NORMAL Or "
 If (lVal And FILE_ATTRIBUTE_COMPRESSED) = FILE_ATTRIBUTE_COMPRESSED Then sRet = sRet & "FILE_ATTRIBUTE_COMPRESSED Or "
 If (lVal And FILE_ATTRIBUTE_ENCRYPTED) = FILE_ATTRIBUTE_ENCRYPTED Then sRet = sRet & "FILE_ATTRIBUTE_ENCRYPTED Or "
 If (lVal And FILE_ATTRIBUTE_REPARSE_POINT) = FILE_ATTRIBUTE_REPARSE_POINT Then sRet = sRet & "FILE_ATTRIBUTE_REPARSE_POINT Or "
 If (lVal And FILE_ATTRIBUTE_SPARSE_FILE) = FILE_ATTRIBUTE_SPARSE_FILE Then sRet = sRet & "FILE_ATTRIBUTE_SPARSE_FILE Or "
 If (lVal And FILE_ATTRIBUTE_INTEGRITY_STREAM) = FILE_ATTRIBUTE_INTEGRITY_STREAM Then sRet = sRet & "FILE_ATTRIBUTE_INTEGRITY_STREAM Or "
 If (lVal And FILE_ATTRIBUTE_NO_SCRUB_DATA) = FILE_ATTRIBUTE_NO_SCRUB_DATA Then sRet = sRet & "FILE_ATTRIBUTE_NO_SCRUB_DATA Or "
 If (lVal And FILE_ATTRIBUTE_RECALL_ON_OPEN) = FILE_ATTRIBUTE_RECALL_ON_OPEN Then sRet = sRet & "FILE_ATTRIBUTE_RECALL_ON_OPEN Or "
 If (lVal And FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS) = FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS Then sRet = sRet & "FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS Or "
 If (lVal And FILE_ATTRIBUTE_VIRTUAL) = FILE_ATTRIBUTE_VIRTUAL Then sRet = sRet & "FILE_ATTRIBUTE_VIRTUAL Or "
If sRet = "" Then sRet = "(unknown)"
If Right$(sRet, 4) = " Or " Then
    sRet = Left$(sRet, Len(sRet) - 4)
End If
GetFILE_ATTRIBUTESStr = sRet
End Function
Public Function GetEventHeaderFlagsStr(lVal As Long) As String
Dim sRet As String
 If (lVal And EVENT_HEADER_FLAG_EXTENDED_INFO) = EVENT_HEADER_FLAG_EXTENDED_INFO Then sRet = sRet & "EVENT_HEADER_FLAG_EXTENDED_INFO Or "
 If (lVal And EVENT_HEADER_FLAG_PRIVATE_SESSION) = EVENT_HEADER_FLAG_PRIVATE_SESSION Then sRet = sRet & "EVENT_HEADER_FLAG_PRIVATE_SESSION Or "
 If (lVal And EVENT_HEADER_FLAG_STRING_ONLY) = EVENT_HEADER_FLAG_STRING_ONLY Then sRet = sRet & "EVENT_HEADER_FLAG_STRING_ONLY Or "
 If (lVal And EVENT_HEADER_FLAG_TRACE_MESSAGE) = EVENT_HEADER_FLAG_TRACE_MESSAGE Then sRet = sRet & "EVENT_HEADER_FLAG_TRACE_MESSAGE Or "
 If (lVal And EVENT_HEADER_FLAG_NO_CPUTIME) = EVENT_HEADER_FLAG_NO_CPUTIME Then sRet = sRet & "EVENT_HEADER_FLAG_NO_CPUTIME Or "
 If (lVal And EVENT_HEADER_FLAG_32_BIT_HEADER) = EVENT_HEADER_FLAG_32_BIT_HEADER Then sRet = sRet & "EVENT_HEADER_FLAG_32_BIT_HEADER Or "
 If (lVal And EVENT_HEADER_FLAG_64_BIT_HEADER) = EVENT_HEADER_FLAG_64_BIT_HEADER Then sRet = sRet & "EVENT_HEADER_FLAG_64_BIT_HEADER Or "
 If (lVal And EVENT_HEADER_FLAG_DECODE_GUID) = EVENT_HEADER_FLAG_DECODE_GUID Then sRet = sRet & "EVENT_HEADER_FLAG_DECODE_GUID Or "
 If (lVal And EVENT_HEADER_FLAG_CLASSIC_HEADER) = EVENT_HEADER_FLAG_CLASSIC_HEADER Then sRet = sRet & "EVENT_HEADER_FLAG_CLASSIC_HEADER Or "
 If (lVal And EVENT_HEADER_FLAG_PROCESSOR_INDEX) = EVENT_HEADER_FLAG_PROCESSOR_INDEX Then sRet = sRet & "EVENT_HEADER_FLAG_PROCESSOR_INDEX Or "
If sRet = "" Then sRet = "(unknown)"
If Right$(sRet, 4) = " Or " Then
    sRet = Left$(sRet, Len(sRet) - 4)
End If
GetEventHeaderFlagsStr = sRet
End Function
Public Function GetFileInfoClassStr(lVal As Long) As String
Dim sRet As String
 If (lVal = 0) Then sRet = "None"
 If (lVal = FileDirectoryInformation) Then sRet = "FileDirectoryInformation"
 If (lVal = FileFullDirectoryInformation) Then sRet = "FileFullDirectoryInformation"
 If (lVal = FileBothDirectoryInformation) Then sRet = "FileBothDirectoryInformation"
 If (lVal = FileBasicInformation) Then sRet = "FileBasicInformation"
 If (lVal = FileStandardInformation) Then sRet = "FileStandardInformation"
 If (lVal = FileInternalInformation) Then sRet = "FileInternalInformation"
 If (lVal = FileEaInformation) Then sRet = "FileEaInformation"
 If (lVal = FileAccessInformation) Then sRet = "FileAccessInformation"
 If (lVal = FileNameInformation) Then sRet = "FileNameInformation"
 If (lVal = FileRenameInformation) Then sRet = "FileRenameInformation"
 If (lVal = FileLinkInformation) Then sRet = "FileLinkInformation"
 If (lVal = FileNamesInformation) Then sRet = "FileNamesInformation"
 If (lVal = FileDispositionInformation) Then sRet = "FileDispositionInformation"
 If (lVal = FilePositionInformation) Then sRet = "FilePositionInformation"
 If (lVal = FileFullEaInformation) Then sRet = "FileFullEaInformation"
 If (lVal = FileModeInformation) Then sRet = "FileModeInformation"
 If (lVal = FileAlignmentInformation) Then sRet = "FileAlignmentInformation"
 If (lVal = FileAllInformation) Then sRet = "FileAllInformation"
 If (lVal = FileAllocationInformation) Then sRet = "FileAllocationInformation"
 If (lVal = FileEndOfFileInformation) Then sRet = "FileEndOfFileInformation"
 If (lVal = FileAlternateNameInformation) Then sRet = "FileAlternateNameInformation"
 If (lVal = FileStreamInformation) Then sRet = "FileStreamInformation"
 If (lVal = FilePipeInformation) Then sRet = "FilePipeInformation"
 If (lVal = FilePipeLocalInformation) Then sRet = "FilePipeLocalInformation"
 If (lVal = FilePipeRemoteInformation) Then sRet = "FilePipeRemoteInformation"
 If (lVal = FileMailslotQueryInformation) Then sRet = "FileMailslotQueryInformation"
 If (lVal = FileMailslotSetInformation) Then sRet = "FileMailslotSetInformation"
 If (lVal = FileCompressionInformation) Then sRet = "FileCompressionInformation"
 If (lVal = FileCopyOnWriteInformation) Then sRet = "FileCopyOnWriteInformation"
 If (lVal = FileCompletionInformation) Then sRet = "FileCompletionInformation"
 If (lVal = FileMoveClusterInformation) Then sRet = "FileMoveClusterInformation"
 If (lVal = FileQuotaInformation) Then sRet = "FileQuotaInformation"
 If (lVal = FileReparsePointInformation) Then sRet = "FileReparsePointInformation"
 If (lVal = FileNetworkOpenInformation) Then sRet = "FileNetworkOpenInformation"
 If (lVal = FileObjectIdInformation) Then sRet = "FileObjectIdInformation"
 If (lVal = FileTrackingInformation) Then sRet = "FileTrackingInformation"
 If (lVal = FileOleDirectoryInformation) Then sRet = "FileOleDirectoryInformation"
 If (lVal = FileContentIndexInformation) Then sRet = "FileContentIndexInformation"
 If (lVal = FileInheritContentIndexInformation) Then sRet = "FileInheritContentIndexInformation"
 If (lVal = FileOleInformation) Then sRet = "FileOleInformation"
 If (lVal = FileMaximumInformation) = FileMaximumInformation Then sRet = "FileMaximumInformation"
If sRet = "" Then sRet = CStr(lVal) & " (unknown)"
GetFileInfoClassStr = sRet
End Function
Public Function GetIrpFlagsStr(lVal As Long) As String
If lVal = 0& Then
    GetIrpFlagsStr = "None"
    Exit Function
End If
Dim sRet As String
 If (lVal And IRP_NOCACHE) = IRP_NOCACHE Then sRet = sRet & "IRP_NOCACHE Or "
 If (lVal And IRP_PAGING_IO) = IRP_PAGING_IO Then sRet = sRet & "IRP_PAGING_IO Or "
 If (lVal And IRP_MOUNT_COMPLETION) = IRP_MOUNT_COMPLETION Then sRet = sRet & "IRP_MOUNT_COMPLETION Or "
 If (lVal And IRP_SYNCHRONOUS_API) = IRP_SYNCHRONOUS_API Then sRet = sRet & "IRP_SYNCHRONOUS_API Or "
 If (lVal And IRP_ASSOCIATED_IRP) = IRP_ASSOCIATED_IRP Then sRet = sRet & "IRP_ASSOCIATED_IRP Or "
 If (lVal And IRP_BUFFERED_IO) = IRP_BUFFERED_IO Then sRet = sRet & "IRP_BUFFERED_IO Or "
 If (lVal And IRP_DEALLOCATE_BUFFER) = IRP_DEALLOCATE_BUFFER Then sRet = sRet & "IRP_DEALLOCATE_BUFFER Or "
 If (lVal And IRP_INPUT_OPERATION) = IRP_INPUT_OPERATION Then sRet = sRet & "IRP_INPUT_OPERATION Or "
 If (lVal And IRP_SYNCHRONOUS_PAGING_IO) = IRP_SYNCHRONOUS_PAGING_IO Then sRet = sRet & "IRP_SYNCHRONOUS_PAGING_IO Or "
 If (lVal And IRP_CREATE_OPERATION) = IRP_CREATE_OPERATION Then sRet = sRet & "IRP_CREATE_OPERATION Or "
 If (lVal And IRP_READ_OPERATION) = IRP_READ_OPERATION Then sRet = sRet & "IRP_READ_OPERATION Or "
 If (lVal And IRP_WRITE_OPERATION) = IRP_WRITE_OPERATION Then sRet = sRet & "IRP_WRITE_OPERATION Or "
 If (lVal And IRP_CLOSE_OPERATION) = IRP_CLOSE_OPERATION Then sRet = sRet & "IRP_CLOSE_OPERATION Or "
 If (lVal And IRP_DEFER_IO_COMPLETION) = IRP_DEFER_IO_COMPLETION Then sRet = sRet & "IRP_DEFER_IO_COMPLETION Or "
 If (lVal And IRP_OB_QUERY_NAME) = IRP_OB_QUERY_NAME Then sRet = sRet & "IRP_OB_QUERY_NAME Or "
 If (lVal And IRP_HOLD_DEVICE_QUEUE) = IRP_HOLD_DEVICE_QUEUE Then sRet = sRet & "IRP_HOLD_DEVICE_QUEUE Or "
 If (lVal And IRP_QUOTA_CHARGED) = IRP_QUOTA_CHARGED Then sRet = sRet & "IRP_QUOTA_CHARGED Or "
 If (lVal And IRP_ALLOCATED_MUST_SUCCEED) = IRP_ALLOCATED_MUST_SUCCEED Then sRet = sRet & "IRP_ALLOCATED_MUST_SUCCEED Or "
 If (lVal And IRP_ALLOCATED_FIXED_SIZE) = IRP_ALLOCATED_FIXED_SIZE Then sRet = sRet & "IRP_ALLOCATED_FIXED_SIZE Or "
 If (lVal And IRP_LOOKASIDE_ALLOCATION) = IRP_LOOKASIDE_ALLOCATION Then sRet = sRet & "IRP_LOOKASIDE_ALLOCATION Or "
If sRet = "" Then sRet = "(unknown)"
If Right$(sRet, 4) = " Or " Then
    sRet = Left$(sRet, Len(sRet) - 4)
End If
GetIrpFlagsStr = sRet
End Function
Public Function GetShareStr(dwShare As Integer) As String
If dwShare = FILE_SHARE_ALL Then
    GetShareStr = "FILE_SHARE_ALL"
    Exit Function
Else
    If (dwShare And FILE_SHARE_READ) Then GetShareStr = "FILE_SHARE_READ Or "
    If (dwShare And FILE_SHARE_WRITE) Then GetShareStr = GetShareStr & "FILE_SHARE_WRITE Or "
    If (dwShare And FILE_SHARE_DELETE) Then GetShareStr = GetShareStr & "FILE_SHARE_DELETE"
    If GetShareStr = "" Then GetShareStr = "NULL"
    If Right$(GetShareStr, 4) = " Or " Then
        GetShareStr = Left$(GetShareStr, Len(GetShareStr) - 4)
    End If
End If
End Function

