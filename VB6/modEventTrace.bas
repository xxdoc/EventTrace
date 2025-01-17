Attribute VB_Name = "modEventTrace"
Option Explicit
Private Declare Function IsValidSid Lib "advapi32" (ByVal psid As Long) As Long
Private Declare Function GetLengthSid Lib "advapi32" (psid As Any) As Long
Private Declare Function ConvertSidToStringSid Lib "advapi32" Alias "ConvertSidToStringSidW" (ByVal Sid As Long, StringSid As Long) As Long

'********************************************************************
'modEventTrace - Event Trace Definitions
'
'Contains definitions neccessary to implement a Windows Event Tracing
'consumer in VB.
'
'Includes all defs neccessary for a kernel logger, and some additional
'defs for provisioning, but is not a complete implementation of evntrace.h
'
'There a large amount of MOF types that have not been included either;
'I'll add more in the future but wanted to focus on getting the initial
'version out.
'********************************************************************

'****************************
'IMPORTS
'Dependencies from other headers

'In this project, MAX_PATH is adjusted upward...
'We receive paths like \Device\HarddiskvolumeShadowCopy12\path\etc where
'the prefix and volume (DOS device name) don't count towards the limit.
Public Const MAX_PATH_DOS = 300

Public Type GUID
   Data1 As Long
   Data2 As Integer
   Data3 As Integer
   Data4(7) As Byte
End Type
Public Type LARGE_INTEGER
    lowPart As Long
    highPart As Long
End Type
Public Type SYSTEMTIME
    wYear As Integer
    wMonth As Integer
    wDayOfWeek As Integer
    wDay As Integer
    wHour As Integer
    wMinute As Integer
    wSecond As Integer
    wMilliseconds As Integer
End Type
Public Type FILETIME
  dwLowDateTime As Long
  dwHighDateTime As Long
End Type
Public Type TIME_ZONE_INFORMATION
    Bias As Long
    StandardName(0 To 31) As Integer
    StandardDate As SYSTEMTIME
    StandardBias As Long
    DaylightName(0 To 31) As Integer
    DaylightDate As SYSTEMTIME
    DaylightBias As Long
End Type
Public Const ERROR_SUCCESS = 0&
Public Const ERROR_BAD_LENGTH = 24&
Public Const ERROR_INVALID_PARAMETER = 87
Public Const ERROR_BAD_PATHNAME = 161&
Public Const ERROR_MORE_DATA = 234
Public Const ERROR_ACCESS_DENIED = 5&
Public Const ERROR_WMI_INSTANCE_NOT_FOUND = 4201
Public Const ERROR_ALREADY_EXISTS = 183&
Public Const ERROR_DISK_FULL = 112&
Public Const ERROR_NO_SYSTEM_RESOURCES = 1450
Public Const ERROR_INSUFFICIENT_BUFFER = 122
Public Const ERROR_CTX_CLOSE_PENDING = &H1B5F
Public Const FILE_SUPERSEDED = &H0
Public Const FILE_OPENED = &H1
Public Const FILE_CREATED = &H2
Public Const FILE_OVERWRITTEN = &H3
Public Const FILE_EXISTS = &H4
Public Const FILE_DOES_NOT_EXIST = &H5
Public Enum FILE_ATTRIBUTES
    INVALID_FILE_ATTRIBUTES = -1
    FILE_ATTRIBUTE_READONLY = &H1
    FILE_ATTRIBUTE_HIDDEN = &H2
    FILE_ATTRIBUTE_SYSTEM = &H4
    FILE_ATTRIBUTE_ARCHIVE = &H20
    FILE_ATTRIBUTE_TEMPORARY = &H100
    FILE_ATTRIBUTE_OFFLINE = &H1000
    FILE_ATTRIBUTE_NOT_CONTENT_INDEXED = &H2000
    'Values below this point can only be read, not set
    FILE_ATTRIBUTE_DIRECTORY = &H10
    FILE_ATTRIBUTE_DEVICE = &H40
    FILE_ATTRIBUTE_NORMAL = &H80
    FILE_ATTRIBUTE_COMPRESSED = &H800
    FILE_ATTRIBUTE_ENCRYPTED = &H4000
    FILE_ATTRIBUTE_REPARSE_POINT = &H400
    FILE_ATTRIBUTE_SPARSE_FILE = &H200
    FILE_ATTRIBUTE_INTEGRITY_STREAM = &H8000
    FILE_ATTRIBUTE_NO_SCRUB_DATA = &H20000
    FILE_ATTRIBUTE_RECALL_ON_OPEN = &H40000
    FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = &H400000
    FILE_ATTRIBUTE_VIRTUAL = &H10000
End Enum
Public Enum CreateOpts
    '// Create disposition
    FILE_SUPERSEDE = &H0
    FILE_OPEN = &H1
    FILE_CREATE = &H2
    FILE_OPEN_IF = &H3
    FILE_OVERWRITE = &H4
    FILE_OVERWRITE_IF = &H5
    FILE_MAXIMUM_DISPOSITION = &H5
    
    '// Create/open flags
    FILE_DIRECTORY_FILE = &H1
    FILE_WRITE_THROUGH = &H2
    FILE_SEQUENTIAL_ONLY = &H4
    FILE_NO_INTERMEDIATE_BUFFERING = &H8
    
    FILE_SYNCHRONOUS_IO_ALERT = &H10
    FILE_SYNCHRONOUS_IO_NONALERT = &H20
    FILE_NON_DIRECTORY_FILE = &H40
    FILE_CREATE_TREE_CONNECTION = &H80
    
    FILE_COMPLETE_IF_OPLOCKED = &H100
    FILE_NO_EA_KNOWLEDGE = &H200
    FILE_OPEN_FOR_RECOVERY = &H400
    FILE_RANDOM_ACCESS = &H800
    
    FILE_DELETE_ON_CLOSE = &H1000
    FILE_OPEN_BY_FILE_ID = &H2000
    FILE_OPEN_FOR_BACKUP_INTENT = &H4000
    FILE_NO_COMPRESSION = &H8000
    FILE_OPEN_REQUIRING_OPLOCK = &H10000
    FILE_DISALLOW_EXCLUSIVE = &H20000
    FILE_SESSION_AWARE = &H40000
    
    FILE_RESERVE_OPFILTER = &H100000
    FILE_OPEN_REPARSE_POINT = &H200000
    FILE_OPEN_NO_RECALL = &H400000
    FILE_OPEN_FOR_FREE_SPACE_QUERY = &H800000
End Enum
Public Enum IrpFlags
    IRP_NOCACHE = &H1
    IRP_PAGING_IO = &H2
    IRP_MOUNT_COMPLETION = &H2
    IRP_SYNCHRONOUS_API = &H4
    IRP_ASSOCIATED_IRP = &H8
    IRP_BUFFERED_IO = &H10
    IRP_DEALLOCATE_BUFFER = &H20
    IRP_INPUT_OPERATION = &H40
    IRP_SYNCHRONOUS_PAGING_IO = &H40
    IRP_CREATE_OPERATION = &H80
    IRP_READ_OPERATION = &H100
    IRP_WRITE_OPERATION = &H200
    IRP_CLOSE_OPERATION = &H400
    IRP_DEFER_IO_COMPLETION = &H800
    IRP_OB_QUERY_NAME = &H1000
    IRP_HOLD_DEVICE_QUEUE = &H2000
'  Define I/O request packet (IRP) alternate flags for allocation control.
    IRP_QUOTA_CHARGED = &H1
    IRP_ALLOCATED_MUST_SUCCEED = &H2
    IRP_ALLOCATED_FIXED_SIZE = &H4
    IRP_LOOKASIDE_ALLOCATION = &H8
End Enum

Public Enum FILE_INFORMATION_CLASS
    FileDirectoryInformation = 1
    FileFullDirectoryInformation = 2
    FileBothDirectoryInformation = 3
    FileBasicInformation = 4
    FileStandardInformation = 5
    FileInternalInformation = 6
    FileEaInformation = 7
    FileAccessInformation = 8
    FileNameInformation = 9
    FileRenameInformation = 10
    FileLinkInformation = 11
    FileNamesInformation = 12
    FileDispositionInformation = 13
    FilePositionInformation = 14
    FileFullEaInformation = 15
    FileModeInformation = 16
    FileAlignmentInformation = 17
    FileAllInformation = 18
    FileAllocationInformation = 19
    FileEndOfFileInformation = 20
    FileAlternateNameInformation = 21
    FileStreamInformation = 22
    FilePipeInformation = 23
    FilePipeLocalInformation = 24
    FilePipeRemoteInformation = 25
    FileMailslotQueryInformation = 26
    FileMailslotSetInformation = 27
    FileCompressionInformation = 28
    FileCopyOnWriteInformation = 29
    FileCompletionInformation = 30
    FileMoveClusterInformation = 31
    FileQuotaInformation = 32
    FileReparsePointInformation = 33
    FileNetworkOpenInformation = 34
    FileObjectIdInformation = 35
    FileTrackingInformation = 36
    FileOleDirectoryInformation = 37
    FileContentIndexInformation = 38
    FileInheritContentIndexInformation = 39
    FileOleInformation = 40
    FileMaximumInformation = 41
End Enum

Public Const FILE_SHARE_READ As Integer = 1
Public Const FILE_SHARE_WRITE As Integer = 2
Public Const FILE_SHARE_DELETE As Integer = 4
Public Const FILE_SHARE_ALL As Integer = FILE_SHARE_READ Or FILE_SHARE_WRITE Or FILE_SHARE_DELETE

'**************************
'evntrace.h, evntcons.h, wmicore.mof

Public Const KERNEL_LOGGER_NAMEW = "NT Kernel Logger"
Public Const GLOBAL_LOGGER_NAMEW = "GlobalLogger"
Public Const EVENT_LOGGER_NAMEW = "EventLog"
Public Const DIAG_LOGGER_NAMEW = "DiagLog"
Public Const SYSTEM_EVENT_TYPE = 1
Public Const MAX_MOF_FIELDS = 16

Public Const gRundownName = "TraceRndnActivVB"

Public Const WNODE_FLAG_TRACED_GUID = &H20000

Public Type WNODE_HEADER          'typedef struct WNODE_HEADER {
    BufferSize As Long            'ULONG BufferSize;
    ProviderId As Long            'ULONG ProviderId;
    HistoricalContext As Currency 'union {
                                  '      ULONG64 HistoricalContext;
                                  '      struct {
                                  '        ULONG Version;
                                  '        ULONG Linkage;
                                  '      };
                                  '    };
    TimeStamp As LARGE_INTEGER    'union {
                                  '    HANDLE        KernelHandle;
                                  '    LARGE_INTEGER TimeStamp;
                                  '  };
    tGUID As GUID                 'GUID  Guid;
    ClientContext As Long         'ULONG ClientContext;
    Flags As Long                 'ULONG Flags;
End Type                          '};

Public Type EVENT_TRACE_PROPERTIES 'typedef struct _EVENT_TRACE_PROPERTIES {
    Wnode As WNODE_HEADER          'WNODE_HEADER Wnode;
    BufferSize As Long             'ULONG BufferSize;                   // buffer size for logging (kbytes)
    MinimumBuffers As Long         'ULONG MinimumBuffers;               // minimum to preallocate
    MaximumBuffers As Long         'ULONG MaximumBuffers;               // maximum buffers allowed
    MaximumFileSize As Long        'ULONG MaximumFileSize;              // maximum logfile size (in MBytes)
    LogFileMode As LoggerModeFlags 'ULONG LogFileMode;                  // sequential, circular
    FlushTimer As Long             'ULONG FlushTimer;                   // buffer flush timer, in seconds
    EnableFlags As EventTraceFlags 'ULONG EnableFlags;                  // trace enable flags
    FlushThreshold As Long         '  union {
                                   '    LONG AgeLimit 'MSDN: Not used.
                                   '    LONG  FlushThreshold;           // Number of buffers to fill before flushing
                                   '  } DUMMYUNIONNAME
    NumberOfBuffers As Long        'ULONG NumberOfBuffers;              // no of buffers in use
    FreeBuffers As Long            'ULONG FreeBuffers;                  // no of buffers free
    EventsLost As Long             'ULONG EventsLost;                   // event records lost
    BuffersWritten As Long         'ULONG BuffersWritten;               // no of buffers written to file
    LogBuffersLost As Long         'ULONG LogBuffersLost;               // no of logfile write failures
    RealTimeBuffersLost As Long    'ULONG RealTimeBuffersLost;          // no of rt delivery failures
    LoggerThreadId As Long         'HANDLE LoggerThreadId;              // thread id of Logger
    LogFileNameOffset As Long      'ULONG LogFileNameOffset;            // Offset to LogFileName
    LoggerNameOffset As Long       'ULONG LoggerNameOffset;             // Offset to LoggerName
End Type                           '} EVENT_TRACE_PROPERTIES, *PEVENT_TRACE_PROPERTIES;

Public Type EtpKernelTrace
    tProp As EVENT_TRACE_PROPERTIES
    padding(0 To 3) As Byte
    LoggerName(0 To 31) As Byte 'LenB(KERNEL_LOGGER_NAMEW)
    padding2(0 To 3) As Byte
End Type

Public Type EVENT_TRACE_PROPERTIES_V2       'typedef struct _EVENT_TRACE_PROPERTIES_V2 {
    Wnode As WNODE_HEADER                   'WNODE_HEADER Wnode;
    BufferSize As Long                      'ULONG BufferSize;                   // buffer size for logging (kbytes)
    MinimumBuffers As Long                  'ULONG MinimumBuffers;               // minimum to preallocate
    MaximumBuffers As Long                  'ULONG MaximumBuffers;               // maximum buffers allowed
    MaximumFileSize As Long                 'ULONG MaximumFileSize;              // maximum logfile size (in MBytes)
    LogFileMode As LoggerModeFlags          'ULONG LogFileMode;                  // sequential, circular
    FlushTimer As Long                      'ULONG FlushTimer;                   // buffer flush timer, in seconds
    EnableFlags As EventTraceFlags          'ULONG EnableFlags;                  // trace enable flags
    FlushThreshold As Long                  '  union {
                                            '    LONG AgeLimit 'MSDN: Not used.
                                            '    LONG  FlushThreshold;           // Number of buffers to fill before flushing
                                            '  } DUMMYUNIONNAME
    NumberOfBuffers As Long                 'ULONG NumberOfBuffers;              // no of buffers in use
    FreeBuffers As Long                     'ULONG FreeBuffers;                  // no of buffers free
    EventsLost As Long                      'ULONG EventsLost;                   // event records lost
    BuffersWritten As Long                  'ULONG BuffersWritten;               // no of buffers written to file
    LogBuffersLost As Long                  'ULONG LogBuffersLost;               // no of logfile write failures
    RealTimeBuffersLost As Long             'ULONG RealTimeBuffersLost;          // no of rt delivery failures
    LoggerThreadId As Long                  'HANDLE LoggerThreadId;              // thread id of Logger
    LogFileNameOffset As Long               'ULONG LogFileNameOffset;            // Offset to LogFileName
    LoggerNameOffset As Long                'ULONG LoggerNameOffset;             // Offset to LoggerName
                                            'union {
                                            '    struct {
                                            '      ULONG VersionNumber : 8;
                                            '    } DUMMYSTRUCTNAME;
    V2Control As Long                       '    ULONG V2Control;
                                            '  } DUMMYUNIONNAME2;
    FilterDescCount As Long                 '  ULONG                    FilterDescCount;
    FilterDesc As Long 'VarPtr to structure '  PEVENT_FILTER_DESCRIPTOR FilterDesc;
                                            '  union {
                                            '    struct {
    Wow As Long                             '      ULONG Wow : 1;
    QpcDeltaTracking As Long                '      ULONG QpcDeltaTracking : 1;
    LargeMdlPages As Long                   '      ULONG LargeMdlPages : 1;
    ExcludeKernelStack As Long              '      ULONG ExcludeKernelStack : 1;
                                            '    } DUMMYSTRUCTNAME;
                                            '    ULONG64 V2Options;
                                            '  } DUMMYUNIONNAME3;
End Type                                '} EVENT_TRACE_PROPERTIES_V2, *PEVENT_TRACE_PROP


Public Const PROCESS_TRACE_MODE_REAL_TIME = &H100
Public Const PROCESS_TRACE_MODE_RAW_TIMESTAMP = &H1000
Public Const PROCESS_TRACE_MODE_EVENT_RECORD = &H10000000


Public Const EVENT_TRACE_TYPE_INFO As Byte = &H0 ' Info or point event
Public Const EVENT_TRACE_TYPE_START As Byte = &H1 ' Start event
Public Const EVENT_TRACE_TYPE_END As Byte = &H2 ' End event
Public Const EVENT_TRACE_TYPE_STOP As Byte = &H2 ' Stop event (WinEvent compatible)
Public Const EVENT_TRACE_TYPE_DC_START As Byte = &H3 ' Collection start marker
Public Const EVENT_TRACE_TYPE_DC_END As Byte = &H4 ' Collection end marker
Public Const EVENT_TRACE_TYPE_EXTENSION As Byte = &H5 ' Extension/continuation
Public Const EVENT_TRACE_TYPE_REPLY As Byte = &H6 ' Reply event
Public Const EVENT_TRACE_TYPE_DEQUEUE As Byte = &H7 ' De-queue event
Public Const EVENT_TRACE_TYPE_RESUME As Byte = &H7 ' Resume event (WinEvent compatible)
Public Const EVENT_TRACE_TYPE_CHECKPOINT As Byte = &H8 ' Generic checkpoint event
Public Const EVENT_TRACE_TYPE_SUSPEND As Byte = &H8 ' Suspend event (WinEvent compatible)
Public Const EVENT_TRACE_TYPE_WINEVT_SEND As Byte = &H9 ' Send Event (WinEvent compatible)
Public Const EVENT_TRACE_TYPE_WINEVT_RECEIVE As Byte = &HF0   ' Receive Event (WinEvent compatible)
 
Public Const EVENT_TRACE_TYPE_LOAD As Byte = &HA ' Load image
Public Const EVENT_TRACE_TYPE_TERMINATE As Byte = &HB ' Terminate Process
'  Event types for IO subsystem
Public Const EVENT_TRACE_TYPE_IO_READ As Byte = &HA
Public Const EVENT_TRACE_TYPE_IO_WRITE As Byte = &HB
Public Const EVENT_TRACE_TYPE_IO_READ_INIT As Byte = &HC
Public Const EVENT_TRACE_TYPE_IO_WRITE_INIT As Byte = &HD
Public Const EVENT_TRACE_TYPE_IO_FLUSH As Byte = &HE
Public Const EVENT_TRACE_TYPE_IO_FLUSH_INIT As Byte = &HF
Public Const EVENT_TRACE_TYPE_IO_REDIRECTED_INIT As Byte = &H10
'  Event types for Memory subsystem
Public Const EVENT_TRACE_TYPE_MM_TF As Byte = &HA ' Transition fault
Public Const EVENT_TRACE_TYPE_MM_DZF As Byte = &HB ' Demand Zero fault
Public Const EVENT_TRACE_TYPE_MM_COW As Byte = &HC ' Copy on Write
Public Const EVENT_TRACE_TYPE_MM_GPF As Byte = &HD ' Guard Page fault
Public Const EVENT_TRACE_TYPE_MM_HPF As Byte = &HE ' Hard page fault
Public Const EVENT_TRACE_TYPE_MM_AV As Byte = &HF ' Access violation
'  Event types for Network subsystem, all protocols
Public Const EVENT_TRACE_TYPE_SEND As Byte = &HA ' Send
Public Const EVENT_TRACE_TYPE_RECEIVE As Byte = &HB ' Receive
Public Const EVENT_TRACE_TYPE_CONNECT As Byte = &HC ' Connect
Public Const EVENT_TRACE_TYPE_DISCONNECT As Byte = &HD ' Disconnect
Public Const EVENT_TRACE_TYPE_RETRANSMIT As Byte = &HE ' ReTransmit
Public Const EVENT_TRACE_TYPE_ACCEPT As Byte = &HF ' Accept
Public Const EVENT_TRACE_TYPE_RECONNECT As Byte = &H10   ' ReConnect
Public Const EVENT_TRACE_TYPE_CONNFAIL As Byte = &H11   ' Fail
Public Const EVENT_TRACE_TYPE_COPY_TCP As Byte = &H12   ' Copy in PendData
Public Const EVENT_TRACE_TYPE_COPY_ARP As Byte = &H13   ' NDIS_STATUS_RESOURCES Copy
Public Const EVENT_TRACE_TYPE_ACKFULL As Byte = &H14   ' A full data ACK
Public Const EVENT_TRACE_TYPE_ACKPART As Byte = &H15   ' A Partial data ACK
Public Const EVENT_TRACE_TYPE_ACKDUP As Byte = &H16   ' A Duplicate data ACK
'  Event Types for the Header (to handle internal event headers)
Public Const EVENT_TRACE_TYPE_GUIDMAP As Byte = &HA
Public Const EVENT_TRACE_TYPE_CONFIG As Byte = &HB
Public Const EVENT_TRACE_TYPE_SIDINFO As Byte = &HC
Public Const EVENT_TRACE_TYPE_SECURITY As Byte = &HD
Public Const EVENT_TRACE_TYPE_DBGID_RSDS As Byte = &H40
'  Event Types for Registry subsystem
Public Const EVENT_TRACE_TYPE_REGCREATE As Byte = &HA ' NtCreateKey
Public Const EVENT_TRACE_TYPE_REGOPEN As Byte = &HB ' NtOpenKey
Public Const EVENT_TRACE_TYPE_REGDELETE As Byte = &HC ' NtDeleteKey
Public Const EVENT_TRACE_TYPE_REGQUERY As Byte = &HD ' NtQueryKey
Public Const EVENT_TRACE_TYPE_REGSETVALUE As Byte = &HE ' NtSetValueKey
Public Const EVENT_TRACE_TYPE_REGDELETEVALUE As Byte = &HF ' NtDeleteValueKey
Public Const EVENT_TRACE_TYPE_REGQUERYVALUE As Byte = &H10   ' NtQueryValueKey
Public Const EVENT_TRACE_TYPE_REGENUMERATEKEY As Byte = &H11   ' NtEnumerateKey
Public Const EVENT_TRACE_TYPE_REGENUMERATEVALUEKEY As Byte = &H12   ' NtEnumerateValueKey
Public Const EVENT_TRACE_TYPE_REGQUERYMULTIPLEVALUE As Byte = &H13   ' NtQueryMultipleValueKey
Public Const EVENT_TRACE_TYPE_REGSETINFORMATION As Byte = &H14   ' NtSetInformationKey
Public Const EVENT_TRACE_TYPE_REGFLUSH As Byte = &H15   ' NtFlushKey
Public Const EVENT_TRACE_TYPE_REGKCBCREATE As Byte = &H16   ' KcbCreate
Public Const EVENT_TRACE_TYPE_REGKCBDELETE As Byte = &H17   ' KcbDelete
Public Const EVENT_TRACE_TYPE_REGKCBRUNDOWNBEGIN As Byte = &H18   ' KcbRundownBegin
Public Const EVENT_TRACE_TYPE_REGKCBRUNDOWNEND As Byte = &H19   ' KcbRundownEnd
Public Const EVENT_TRACE_TYPE_REGVIRTUALIZE As Byte = &H1A   ' VirtualizeKey
Public Const EVENT_TRACE_TYPE_REGCLOSE As Byte = &H1B   ' NtClose (KeyObject)
Public Const EVENT_TRACE_TYPE_REGSETSECURITY As Byte = &H1C   ' SetSecurityDescriptor (KeyObject)
Public Const EVENT_TRACE_TYPE_REGQUERYSECURITY As Byte = &H1D   ' QuerySecurityDescriptor (KeyObject)
Public Const EVENT_TRACE_TYPE_REGCOMMIT As Byte = &H1E   ' CmKtmNotification (TRANSACTION_NOTIFY_COMMIT)
Public Const EVENT_TRACE_TYPE_REGPREPARE As Byte = &H1F   ' CmKtmNotification (TRANSACTION_NOTIFY_PREPARE)
Public Const EVENT_TRACE_TYPE_REGROLLBACK As Byte = &H20   ' CmKtmNotification (TRANSACTION_NOTIFY_ROLLBACK)
Public Const EVENT_TRACE_TYPE_REGMOUNTHIVE As Byte = &H21   ' NtLoadKey variations + system hives
'  Event types for system configuration records
Public Const EVENT_TRACE_TYPE_CONFIG_CPU As Byte = &HA ' CPU Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_PHYSICALDISK As Byte = &HB ' Physical Disk Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_LOGICALDISK As Byte = &HC ' Logical Disk Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_NIC As Byte = &HD ' NIC Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_VIDEO As Byte = &HE ' Video Adapter Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_SERVICES As Byte = &HF ' Active Services
Public Const EVENT_TRACE_TYPE_CONFIG_POWER As Byte = &H10   ' ACPI Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_NETINFO As Byte = &H11   ' Networking Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_OPTICALMEDIA As Byte = &H12   ' Optical Media Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_IRQ As Byte = &H15   ' IRQ assigned to devices
Public Const EVENT_TRACE_TYPE_CONFIG_PNP As Byte = &H16   ' PnP device info
Public Const EVENT_TRACE_TYPE_CONFIG_IDECHANNEL As Byte = &H17   ' Primary/Secondary IDE channel Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_NUMANODE As Byte = &H18   ' Numa configuration
Public Const EVENT_TRACE_TYPE_CONFIG_PLATFORM As Byte = &H19   ' Platform Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_PROCESSORGROUP As Byte = &H1A   ' Processor Group Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_PROCESSORNUMBER As Byte = &H1B   ' ProcessorIndex -> ProcNumber mapping
Public Const EVENT_TRACE_TYPE_CONFIG_DPI As Byte = &H1C   ' Display DPI Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_CI_INFO As Byte = &H1D   ' Display System Code Integrity Information
Public Const EVENT_TRACE_TYPE_CONFIG_MACHINEID As Byte = &H1E   ' SQM Machine Id
Public Const EVENT_TRACE_TYPE_CONFIG_DEFRAG As Byte = &H1F   ' Logical Disk Defragmenter Information
Public Const EVENT_TRACE_TYPE_CONFIG_MOBILEPLATFORM As Byte = &H20   ' Mobile Platform Configuration
Public Const EVENT_TRACE_TYPE_CONFIG_DEVICEFAMILY As Byte = &H21   ' Device Family Information
Public Const EVENT_TRACE_TYPE_CONFIG_FLIGHTID As Byte = &H22   ' Flights on the machine
Public Const EVENT_TRACE_TYPE_CONFIG_PROCESSOR As Byte = &H23   ' CentralProcessor records
'  Event types for Optical IO subsystem
Public Const EVENT_TRACE_TYPE_OPTICAL_IO_READ As Byte = &H37
Public Const EVENT_TRACE_TYPE_OPTICAL_IO_WRITE As Byte = &H38
Public Const EVENT_TRACE_TYPE_OPTICAL_IO_FLUSH As Byte = &H39
Public Const EVENT_TRACE_TYPE_OPTICAL_IO_READ_INIT As Byte = &H3A
Public Const EVENT_TRACE_TYPE_OPTICAL_IO_WRITE_INIT As Byte = &H3B
Public Const EVENT_TRACE_TYPE_OPTICAL_IO_FLUSH_INIT As Byte = &H3C
'  Event types for Filter Manager
Public Const EVENT_TRACE_TYPE_FLT_PREOP_INIT As Byte = &H60   ' Minifilter preop initiation
Public Const EVENT_TRACE_TYPE_FLT_POSTOP_INIT As Byte = &H61   ' Minifilter postop initiation
Public Const EVENT_TRACE_TYPE_FLT_PREOP_COMPLETION As Byte = &H62   ' Minifilter preop completion
Public Const EVENT_TRACE_TYPE_FLT_POSTOP_COMPLETION As Byte = &H63   ' Minifilter postop completion
Public Const EVENT_TRACE_TYPE_FLT_PREOP_FAILURE As Byte = &H64   ' Minifilter failed preop
Public Const EVENT_TRACE_TYPE_FLT_POSTOP_FAILURE As Byte = &H65   ' Minifilter failed postop


Public Const TRACE_LEVEL_NONE As Byte = 0   ' Tracing is not on
Public Const TRACE_LEVEL_CRITICAL As Byte = 1    ' Abnormal exit or termination
Public Const TRACE_LEVEL_FATAL As Byte = 1    ' Deprecated name for Abnormal exit or termination
Public Const TRACE_LEVEL_ERROR  As Byte = 2   ' Severe errors that need logging
Public Const TRACE_LEVEL_WARNING As Byte = 3   ' Warnings such as allocation failure
Public Const TRACE_LEVEL_INFORMATION As Byte = 4    ' Includes non-error cases(e.g.,Entry-Exit)
Public Const TRACE_LEVEL_VERBOSE As Byte = 5    ' Detailed traces from intermediate steps
Public Const TRACE_LEVEL_RESERVED6 As Byte = 6
Public Const TRACE_LEVEL_RESERVED7  As Byte = 7
Public Const TRACE_LEVEL_RESERVED8  As Byte = 8
Public Const TRACE_LEVEL_RESERVED9 As Byte = 9

Public Enum EventTraceFlags
'// Enable flags for Kernel Events
    EVENT_TRACE_FLAG_PROCESS = &H1   ' process start & end
    EVENT_TRACE_FLAG_THREAD = &H2   ' thread start & end
    EVENT_TRACE_FLAG_IMAGE_LOAD = &H4   ' image load
    EVENT_TRACE_FLAG_DISK_IO = &H100 ' physical disk IO
    EVENT_TRACE_FLAG_DISK_FILE_IO = &H200 ' requires disk IO
    EVENT_TRACE_FLAG_MEMORY_PAGE_FAULTS = &H1000 ' all page faults
    EVENT_TRACE_FLAG_MEMORY_HARD_FAULTS = &H2000 ' hard faults only
    EVENT_TRACE_FLAG_NETWORK_TCPIP = &H10000   ' tcpip send & receive
    EVENT_TRACE_FLAG_REGISTRY = &H20000   ' registry calls
    EVENT_TRACE_FLAG_DBGPRINT = &H40000   ' DbgPrint(ex) Calls
'  Enable flags for Kernel Events on Vista and above
    EVENT_TRACE_FLAG_PROCESS_COUNTERS = &H8   ' process perf counters
    EVENT_TRACE_FLAG_CSWITCH = &H10  ' context switches
    EVENT_TRACE_FLAG_DPC = &H20  ' deferred procedure calls
    EVENT_TRACE_FLAG_INTERRUPT = &H40  ' interrupts
    EVENT_TRACE_FLAG_SYSTEMCALL = &H80  ' system calls
    EVENT_TRACE_FLAG_DISK_IO_INIT = &H400 ' physical disk IO initiation
    EVENT_TRACE_FLAG_ALPC = &H100000  ' ALPC traces
    EVENT_TRACE_FLAG_SPLIT_IO = &H200000  ' split io traces (VolumeManager)
    EVENT_TRACE_FLAG_DRIVER = &H800000  ' driver delays
    EVENT_TRACE_FLAG_PROFILE = &H1000000 ' sample based profiling
    EVENT_TRACE_FLAG_FILE_IO = &H2000000 ' file IO
    EVENT_TRACE_FLAG_FILE_IO_INIT = &H4000000 ' file IO initiation
'  Enable flags for Kernel Events on Win7 and above
    EVENT_TRACE_FLAG_DISPATCHER = &H800 ' scheduler (ReadyThread)
    EVENT_TRACE_FLAG_VIRTUAL_ALLOC = &H4000 ' VM operations
'  Enable flags for Kernel Events on Win8 and above
    EVENT_TRACE_FLAG_VAMAP = &H8000 ' map/unmap (excluding images)
    EVENT_TRACE_FLAG_NO_SYSCONFIG = &H10000000   ' Do not do sys config rundown
'  Enable flags for Kernel Events on Threshold and above
    EVENT_TRACE_FLAG_JOB = &H80000   ' job start & end
    EVENT_TRACE_FLAG_DEBUG_EVENTS = &H400000  ' debugger events (break/continue/...)
'  Pre-defined Enable flags for everybody else
    EVENT_TRACE_FLAG_EXTENSION = &H80000000   ' Indicates more flags
    PERF_OB_HANDLE = &H80000040
    EVENT_TRACE_FLAG_FORWARD_WMI = &H40000000   ' Can forward to WMI
    EVENT_TRACE_FLAG_ENABLE_RESERVE = &H20000000   ' Reserved
End Enum

Public Enum LoggerModeFlags
    EVENT_TRACE_FILE_MODE_NONE = &H0          ' Logfile is off
    EVENT_TRACE_FILE_MODE_SEQUENTIAL = &H1          ' Log sequentially
    EVENT_TRACE_FILE_MODE_CIRCULAR = &H2          ' Log in circular manner
    EVENT_TRACE_FILE_MODE_APPEND = &H4          ' Append sequential log
    EVENT_TRACE_REAL_TIME_MODE = &H100        ' Real time mode on
    EVENT_TRACE_DELAY_OPEN_FILE_MODE = &H200        ' Delay opening file
    EVENT_TRACE_BUFFERING_MODE = &H400        ' Buffering mode only
    EVENT_TRACE_PRIVATE_LOGGER_MODE = &H800        ' Process Public Logger
    EVENT_TRACE_ADD_HEADER_MODE = &H1000       ' Add a logfile header
    EVENT_TRACE_USE_GLOBAL_SEQUENCE = &H4000       ' Use global sequence no.
    EVENT_TRACE_USE_LOCAL_SEQUENCE = &H8000       ' Use local sequence no.
    EVENT_TRACE_RELOG_MODE = &H10000      ' Relogger
    EVENT_TRACE_USE_PAGED_MEMORY = &H1000000    ' Use pageable buffers
'  Logger Mode flags on XP and above
    EVENT_TRACE_FILE_MODE_NEWFILE = &H8          ' Auto-switch log file
    EVENT_TRACE_FILE_MODE_PREALLOCATE = &H20         ' Pre-allocate mode
'  Logger Mode flags on Vista and above
    EVENT_TRACE_NONSTOPPABLE_MODE = &H40         ' Session cannot be stopped (Autologger only)
    EVENT_TRACE_SECURE_MODE = &H80         ' Secure session
    EVENT_TRACE_USE_KBYTES_FOR_SIZE = &H2000       ' Use KBytes as file size unit
    EVENT_TRACE_PRIVATE_IN_PROC = &H20000      ' In process Public logger
    EVENT_TRACE_MODE_RESERVED = &H100000     ' Reserved bit, used to signal Heap/Critsec tracing
'  Logger Mode flags on Win7 and above
    EVENT_TRACE_NO_PER_PROCESSOR_BUFFERING = &H10000000   ' Use this for low frequency sessions.
'  Logger Mode flags on Win8 and above
    EVENT_TRACE_SYSTEM_LOGGER_MODE = &H2000000    ' Receive events from SystemTraceProvider
    EVENT_TRACE_ADDTO_TRIAGE_DUMP = &H80000000   ' Add ETW buffers to triage dumps
    EVENT_TRACE_STOP_ON_HYBRID_SHUTDOWN = &H400000     ' Stop on hybrid shutdown
    EVENT_TRACE_PERSIST_ON_HYBRID_SHUTDOWN = &H800000     ' Persist on hybrid shutdown
'  Logger Mode flags on Blue and above
    EVENT_TRACE_INDEPENDENT_SESSION_MODE = &H8000000    ' Independent logger session
'  Logger Mode flags on Redstone and above
    EVENT_TRACE_COMPRESSED_MODE = &H4000000    ' Compressed logger session.
End Enum

Public Enum ControlTraceCodes
    EVENT_TRACE_CONTROL_QUERY = 0
    EVENT_TRACE_CONTROL_STOP = 1
    EVENT_TRACE_CONTROL_UPDATE = 2
    EVENT_TRACE_CONTROL_FLUSH = 3  'Flushes all the buffers
    EVENT_TRACE_CONTROL_INCREMENT_FILE = 4
    EVENT_TRACE_CONTROL_CONVERT_TO_REALTIME = 5
End Enum

Public Enum WMITraceMessages
    TRACE_MESSAGE_SEQUENCE = 1   ' Message should include a sequence number
    TRACE_MESSAGE_GUID = 2   ' Message includes a GUID
    TRACE_MESSAGE_COMPONENTID = 4   ' Message has no GUID, Component ID instead
    TRACE_MESSAGE_TIMESTAMP = 8   ' Message includes a timestamp
    TRACE_MESSAGE_PERFORMANCE_TIMESTAMP = 16   ' *Obsolete* Clock type is controlled by the logger
    TRACE_MESSAGE_SYSTEMINFO = 32   ' Message includes system information TID,PID
'  Vista flags set by system to indicate provider pointer size.
    TRACE_MESSAGE_POINTER32 = &H40     ' Message logged by 32 bit provider
    TRACE_MESSAGE_POINTER64 = &H80     ' Message logged by 64 bit provider
    TRACE_MESSAGE_FLAG_MASK = &HFFFF   ' Only the lower 16 bits of flags are placed in the message
'  those above 16 bits are reserved for local processing
'  Maximum size allowed for a single TraceMessage message.
'  N.B. This limit was increased from 8K to 64K in Win8.
    TRACE_MESSAGE_MAXIMUM_SIZE = 65536 '(64 * 1024)
End Enum

Public Const EVENT_TRACE_USE_PROCTIME = &H1   'ProcessorTime field is valid
Public Const EVENT_TRACE_USE_NOCPUTIME = &H2  'No Kernel/User/Processor Times

Public Enum TraceHeaderFlags
    TRACE_HEADER_FLAG_USE_TIMESTAMP = &H200
    TRACE_HEADER_FLAG_TRACED_GUID = &H20000      ' denotes a trace
    TRACE_HEADER_FLAG_LOG_WNODE = &H40000      ' request to log Wnode
    TRACE_HEADER_FLAG_USE_GUID_PTR = &H80000      ' Guid is actually a pointer
    TRACE_HEADER_FLAG_USE_MOF_PTR = &H100000     ' MOF data are dereferenced
End Enum

Public Enum ETW_COMPRESSION_RESUMPTION_MODE
    EtwCompressionModeRestart = 0
    EtwCompressionModeNoDisable = 1
    EtwCompressionModeNoRestart = 2
End Enum

'Trace header for all legacy events.
'(WHO DESIGNED THIS GARBAGE?)

Public Type EVENT_TRACE_HEADER 'typedef struct _EVENT_TRACE_HEADER {        // overlays WNODE_HEADER
    Size As Integer                'USHORT          Size;                   // Size of entire record
                                   'union {
    FieldTypeFlags As Integer      '    USHORT      FieldTypeFlags;         // Indicates valid fields
                                    'struct {
                                    '           UCHAR   HeaderType              // Header type - internal use only
                                    '           UCHAR   MarkerFlags;            // Marker - internal use only
                                    '        } DUMMYSTRUCTNAME;
                                    '    } DUMMYUNIONNAME;
                                    'union {
    'VersionOrTypeLevelVersion As Long '   ULONG       Version;
                                    '      struct {
    uType As Byte                   '          UCHAR   Type;                   // event type
    uLevel As Byte                  '          UCHAR   Level;                  // trace instrumentation level
    wVersion As Integer             '          USHORT  Version;                // version of trace record
                                    '      } Class;
                                    '  } DUMMYUNIONNAME2;
    ThreadID As Long                'ULONG           ThreadId;               // Thread Id
    ProcessID As Long               'ULONG           ProcessId;              // Process Id
    TimeStamp As LARGE_INTEGER      'LARGE_INTEGER   TimeStamp;              // time when event happens
                                    'union {
    tGUID As GUID                   '    GUID        Guid;                   // Guid that identifies event
                                    '    ULONGLONG   GuidPtr;                // use with WNODE_FLAG_USE_GUID_PTR
                                    '} DUMMYUNIONNAME3;
                                    'union {
    Value1 As Long                  '    struct {
    Value2 As Long                  '        ULONG   KernelTime;             // Kernel Mode CPU ticks
                                    '        ULONG   UserTime;               // User mode CPU ticks
                                    '    } DUMMYSTRUCTNAME;
                                    '    ULONG64     ProcessorTime;          // Processor Clock
                                    '    struct {
                                    '        ULONG   ClientContext;          // Reserved
                                    '        ULONG   Flags;                  // Event Flags
                                    '    } DUMMYSTRUCTNAME2;
                                    '} DUMMYUNIONNAME4;
End Type  '48 Bytes, qword aligned  '} EVENT_TRACE_HEADER, *PEVENT_TRACE_HEADER;
Public Type EVENT_TRACE             'typedef struct _EVENT_TRACE {
    Header As EVENT_TRACE_HEADER    '    EVENT_TRACE_HEADER      Header;             // Event trace header
    InstanceId As Long              '    ULONG                   InstanceId;         // Instance Id of this event
    ParentInstanceId As Long        '    ULONG                   ParentInstanceId;   // Parent Instance Id.
    ParentGuid As GUID              '    GUID                    ParentGuid;         // Parent Guid;
    MofData As Long                 '    PVOID                   MofData;            // Pointer to Variable Data
    MofLength As Long               '    ULONG                   MofLength;          // Variable Datablock Length
                                    '    union {
    Context As Long                 '        ULONG               ClientContext;
    '84 bytes                       '        ETW_BUFFER_CONTEXT  BufferContext;
    padding(0 To 3) As Byte 'QUARDWORD ALIGN'}DUMMYUNIONNAME;
End Type                            '} EVENT_TRACE, *PEVENT_TRACE;

Public Enum TraceDataTypes
    ETW_NULL_TYPE_VALUE = 0
    ETW_OBJECT_TYPE_VALUE = 1
    ETW_STRING_TYPE_VALUE = 2
    ETW_SBYTE_TYPE_VALUE = 3
    ETW_BYTE_TYPE_VALUE = 4
    ETW_INT16_TYPE_VALUE = 5
    ETW_UINT16_TYPE_VALUE = 6
    ETW_INT32_TYPE_VALUE = 7
    ETW_UINT32_TYPE_VALUE = 8
    ETW_INT64_TYPE_VALUE = 9
    ETW_UINT64_TYPE_VALUE = 10
    ETW_CHAR_TYPE_VALUE = 11
    ETW_SINGLE_TYPE_VALUE = 12
    ETW_DOUBLE_TYPE_VALUE = 13
    ETW_BOOLEAN_TYPE_VALUE = 14
    ETW_DECIMAL_TYPE_VALUE = 15
'  Extended types
    ETW_GUID_TYPE_VALUE = 101
    ETW_ASCIICHAR_TYPE_VALUE = 102
    ETW_ASCIISTRING_TYPE_VALUE = 103
    ETW_COUNTED_STRING_TYPE_VALUE = 104
    ETW_POINTER_TYPE_VALUE = 105
    ETW_SIZET_TYPE_VALUE = 106
    ETW_HIDDEN_TYPE_VALUE = 107
    ETW_BOOL_TYPE_VALUE = 108
    ETW_COUNTED_ANSISTRING_TYPE_VALUE = 109
    ETW_REVERSED_COUNTED_STRING_TYPE_VALUE = 110
    ETW_REVERSED_COUNTED_ANSISTRING_TYPE_VALUE = 111
    ETW_NON_NULL_TERMINATED_STRING_TYPE_VALUE = 112
    ETW_REDUCED_ANSISTRING_TYPE_VALUE = 113
    ETW_REDUCED_STRING_TYPE_VALUE = 114
    ETW_SID_TYPE_VALUE = 115
    ETW_VARIANT_TYPE_VALUE = 116
    ETW_PTVECTOR_TYPE_VALUE = 117
    ETW_WMITIME_TYPE_VALUE = 118
    ETW_DATETIME_TYPE_VALUE = 119
    ETW_REFRENCE_TYPE_VALUE = 120
End Enum

Public Type EVENT_INSTANCE_INFO
    RegHandle As Long
    InstanceId As Long
End Type

Public Type TRACE_GUID_REGISTRATION
    GUID As Long 'LPCUUID ' Guid of data block being registered or updated.
    RegHandle As Long ' Guid Registration Handle is returned.
End Type

Public Type TRACE_GUID_PROPERTIES
    GUID As GUID
    GuidType As Long
    LoggerId As Long
    EnableLevel As Long
    EnableFlags As Long
    IsEnable As Boolean
End Type

Public Const ENABLE_TRACE_PARAMETERS_VERSION = 1
Public Const ENABLE_TRACE_PARAMETERS_VERSION_2 = 2


Public Type EVENT_FILTER_DESCRIPTOR
    ptr As Currency
    Size As Long
    type As EventFilterType
End Type

Public Type ENABLE_TRACE_PARAMETERS         'typedef struct _ENABLE_TRACE_PARAMETERS {
    Version As Long                         '    ULONG                    Version;
    EnableProperty As EnablePropertyFlags   '    ULONG                    EnableProperty;
    ControlFlags As Long                    '    ULONG                    ControlFlags;
    SourceId As GUID                        '    GUID                     SourceId;
    EnableFilterDesc As Long                '    PEVENT_FILTER_DESCRIPTOR EnableFilterDesc;
    FilterDescCount As Long                 '    ULONG                    FilterDescCount;
    Pad(0 To 3) As Byte                     '
End Type                                    '} ENABLE_TRACE_PARAMETERS, *PENABLE_TRACE_PARAMETERS;


Public Enum EnablePropertyFlags
        EVENT_ENABLE_PROPERTY_SID = &H1
        EVENT_ENABLE_PROPERTY_TS_ID = &H2
        EVENT_ENABLE_PROPERTY_STACK_TRACE = &H4
        EVENT_ENABLE_PROPERTY_PSM_KEY = &H8
        EVENT_ENABLE_PROPERTY_IGNORE_KEYWORD_0 = &H10
        EVENT_ENABLE_PROPERTY_PROVIDER_GROUP = &H20
        EVENT_ENABLE_PROPERTY_ENABLE_KEYWORD_0 = &H40
        EVENT_ENABLE_PROPERTY_PROCESS_START_KEY = &H80
        EVENT_ENABLE_PROPERTY_EVENT_KEY = &H100
        EVENT_ENABLE_PROPERTY_EXCLUDE_INPRIVATE = &H200
        EVENT_ENABLE_PROPERTY_ENABLE_SILOS = &H400
        EVENT_ENABLE_PROPERTY_SOURCE_CONTAINER_TRACKING = &H800
End Enum
Public Enum EventControlCodes
    EVENT_CONTROL_CODE_DISABLE_PROVIDER = 0
    EVENT_CONTROL_CODE_ENABLE_PROVIDER = 1
    EVENT_CONTROL_CODE_CAPTURE_STATE = 2
End Enum

Public Type TRACE_LOGFILE_HEADER           'typedef struct _TRACE_LOGFILE_HEADER {
    BufferSize As Long                      '    ULONG           BufferSize;         // Logger buffer size in Kbytes
                                            '    union {
    Version As Long                         '        ULONG       Version;            // Logger version
                                            '        struct {
                                            '            UCHAR   MajorVersion;
                                            '            UCHAR   MinorVersion;
                                            '            UCHAR   SubVersion;
                                            '            UCHAR   SubMinorVersion;
                                            '        } VersionDetail;
                                            '    } DUMMYUNIONNAME;
    ProviderVersion As Long                 '    ULONG           ProviderVersion;    // defaults to NT version
    NumberOfProcessors As Long              '    ULONG           NumberOfProcessors; // Number of Processors
    EndTime As LARGE_INTEGER                '    LARGE_INTEGER   EndTime;            // Time when logger stops
    TimerResolution As Long                 '    ULONG           TimerResolution;    // assumes timer is constant!!!
    MaximumFileSize As Long                 '    ULONG           MaximumFileSize;    // Maximum in Mbytes
    LogFileMode As Long                     '    ULONG           LogFileMode;        // specify logfile mode
    BuffersWritten As Long                  '    ULONG           BuffersWritten;     // used to file start of Circular File
                                            '    union {
                                            '        GUID LogInstanceGuid;           // For RealTime Buffer Delivery
                                            '        struct {
    StartBuffers As Long                    '            ULONG   StartBuffers;       // Count of buffers written at start.
    PointerSize As Long                     '            ULONG   PointerSize;        // Size of pointer type in bits
    EventsLost As Long                      '            ULONG   EventsLost;         // Events lost during log session
    CpuSpeedInMhz As Long                   '            ULONG   CpuSpeedInMHz;      // Cpu Speed in MHz
                                            '        } DUMMYSTRUCTNAME;
                                            '    } DUMMYUNIONNAME2;
                                            '#if defined(_WMIKM_)
                                            '    PWCHAR          LoggerName;
                                            '    PWCHAR          LogFileName;
                                            '    RTL_TIME_ZONE_INFORMATION TimeZone;
                                            '#Else
    LoggerName As Long                      '    LPWSTR          LoggerName;
    LogFileName As Long      '68            '    LPWSTR          LogFileName;
    TimeZone As TIME_ZONE_INFORMATION '172  '    TIME_ZONE_INFORMATION TimeZone;
    tzpadding(0 To 3) As Byte               '#End If
    BootTime As LARGE_INTEGER               '    LARGE_INTEGER   BootTime;
    PerfFreq As LARGE_INTEGER               '    LARGE_INTEGER   PerfFreq;           // Reserved
    StartTime As LARGE_INTEGER              '    LARGE_INTEGER   StartTime;          // Reserved
    ReservedFlags As Long                   '    ULONG           ReservedFlags;      // ClockType
    BuffersLost As Long                     '    ULONG           BuffersLost;
    'lhpad(0 To 3) As Byte
End Type  '272 bytes, qword-aligned         '} TRACE_LOGFILE_HEADER, *PTRACE_LOGFILE_HEADER;

Public Type EVENT_TRACE_LOGFILEW           'typedef struct _EVENT_TRACE_LOGFILEW {
    LogFileName As Long                     '  LPWSTR                        LogFileName;
    LoggerName As Long                      '  LPWSTR                        LoggerName;
    CurrentTime As Currency                 '  LONGLONG                      CurrentTime;
    BuffersRead As Long                     '  ULONG                         BuffersRead;
                                            '  union {
    Mode As Long                            '    ULONG LogFileMode;
                                            '    ULONG ProcessTraceMode;
                                            '  } DUMMYUNIONNAME;
    CurrentEvent As EVENT_TRACE '88A'112    '  EVENT_TRACE                   CurrentEvent;
    LogfileHeader As TRACE_LOGFILE_HEADER   '  TRACE_LOGFILE_HEADER          LogfileHeader;
    BufferCallback As Long                  '  PEVENT_TRACE_BUFFER_CALLBACKW BufferCallback;
    BufferSize As Long                      '  ULONG                         BufferSize;
    Filled As Long                          '  ULONG                         Filled;
    EventsLost As Long                      '  ULONG                         EventsLost;
                                            '  union {
    EventCallback As Long                   '    PEVENT_CALLBACK        EventCallback;
                                            '    PEVENT_RECORD_CALLBACK EventRecordCallback;
                                            '  } DUMMYUNIONNAME2;
    IsKernelTrace As Long                   '  ULONG                         IsKernelTrace;
    Context As Long                         '  PVOID                         Context;
End Type                                    '} EVENT_TRACE_LOGFILEW, *PEVENT_TRACE_LOGFILEW;

Public Enum TRACE_QUERY_INFO_CLASS
    TraceGuidQueryList = 0
    TraceGuidQueryInfo = 1
    TraceGuidQueryProcess = 2
    TraceStackTracingInfo = 3 ' Win7
    TraceSystemTraceEnableFlagsInfo = 4
    TraceSampledProfileIntervalInfo = 5
    TraceProfileSourceConfigInfo = 6
    TraceProfileSourceListInfo = 7
    TracePmcEventListInfo = 8
    TracePmcCounterListInfo = 9
    TraceSetDisallowList = 10
    TraceVersionInfo = 11
    TraceGroupQueryList = 12
    TraceGroupQueryInfo = 13
    TraceDisallowListQuery = 14
    TraceCompressionInfo = 15
    TracePeriodicCaptureStateListInfo = 16
    TracePeriodicCaptureStateInfo = 17
    TraceProviderBinaryTracking = 18
    TraceMaxLoggersQuery = 19
    MaxTraceSetInfoClass = 20
End Enum
Public Type CLASSIC_EVENT_ID
    EventGuid As GUID
    type As Byte
    Reserved(0 To 6) As Byte
End Type

Public Enum EventHeaderProperty
    EVENT_HEADER_PROPERTY_XML = &H1
    EVENT_HEADER_PROPERTY_FORWARDED_XML = &H2
    EVENT_HEADER_PROPERTY_LEGACY_EVENTLOG = &H4
    EVENT_HEADER_PROPERTY_RELOGGABLE = &H8
End Enum
Public Enum EventHeaderExtType
    EVENT_HEADER_EXT_TYPE_RELATED_ACTIVITYID = &H1
    EVENT_HEADER_EXT_TYPE_SID = &H2
    EVENT_HEADER_EXT_TYPE_TS_ID = &H3
    EVENT_HEADER_EXT_TYPE_INSTANCE_INFO = &H4
    EVENT_HEADER_EXT_TYPE_STACK_TRACE32 = &H5
    EVENT_HEADER_EXT_TYPE_STACK_TRACE64 = &H6
    EVENT_HEADER_EXT_TYPE_PEBS_INDEX = &H7
    EVENT_HEADER_EXT_TYPE_PMC_COUNTERS = &H8
    EVENT_HEADER_EXT_TYPE_PSM_KEY = &H9
    EVENT_HEADER_EXT_TYPE_EVENT_KEY = &HA
    EVENT_HEADER_EXT_TYPE_EVENT_SCHEMA_TL = &HB
    EVENT_HEADER_EXT_TYPE_PROV_TRAITS = &HC
    EVENT_HEADER_EXT_TYPE_PROCESS_START_KEY = &HD
    EVENT_HEADER_EXT_TYPE_CONTROL_GUID = &HE
    EVENT_HEADER_EXT_TYPE_MAX = &HF
End Enum
Public Enum EventHeaderFlags
    EVENT_HEADER_FLAG_EXTENDED_INFO = &H1
    EVENT_HEADER_FLAG_PRIVATE_SESSION = &H2
    EVENT_HEADER_FLAG_STRING_ONLY = &H4
    EVENT_HEADER_FLAG_TRACE_MESSAGE = &H8
    EVENT_HEADER_FLAG_NO_CPUTIME = &H10
    EVENT_HEADER_FLAG_32_BIT_HEADER = &H20
    EVENT_HEADER_FLAG_64_BIT_HEADER = &H40
    EVENT_HEADER_FLAG_DECODE_GUID = &H80     ' ProviderId is decode GUID.
    EVENT_HEADER_FLAG_CLASSIC_HEADER = &H100
    EVENT_HEADER_FLAG_PROCESSOR_INDEX = &H200
End Enum

Public Type EVENT_DESCRIPTOR            'typedef struct _EVENT_DESCRIPTOR {
    id As Integer                       '  USHORT    Id;
    Version As Byte                     '  UCHAR     Version;
    Channel As Byte                     '  UCHAR     Channel;
    Level As Byte                       '  UCHAR     Level;
    OpCode As Byte                      '  UCHAR     Opcode;
    Task As Integer                     '  USHORT    Task;
    Keyword As Currency                 '  ULONGLONG Keyword;
End Type                                '} EVENT_DESCRIPTOR, *PEVENT_DESCRIPTOR;

Public Type EVENT_HEADER                'typedef struct _EVENT_HEADER {
    Size As Integer                     '  USHORT           Size;
    HeaderType As Integer               '  USHORT           HeaderType;
    Flags As Integer                    '  USHORT           Flags;           EventHeaderFlags Enum
    EventProperty As Integer            '  USHORT           EventProperty;   EventHeaderProperty Enum
    ThreadID As Long                    '  ULONG            ThreadId;
    ProcessID As Long                   '  ULONG            ProcessId;
    TimeStamp As LARGE_INTEGER          '  LARGE_INTEGER    TimeStamp;
    ProviderId As GUID                  '  GUID             ProviderId;
    EventDescriptor As EVENT_DESCRIPTOR '  EVENT_DESCRIPTOR EventDescriptor;
                                        '  union {
                                        '    struct {
    KernelTime As Long                  '      ULONG KernelTime;
    UserTime As Long                    '      ULONG UserTime;
                                        '    } DUMMYSTRUCTNAME;
                                        '    ULONG64 ProcessorTime;
                                        '  } DUMMYUNIONNAME;
    ActivityGuid As GUID                '  GUID             ActivityId;
End Type                                '} EVENT_HEADER, *PEVENT_HEADER;


Public Type ETW_BUFFER_CONTEXT          'typedef struct _ETW_BUFFER_CONTEXT {
                                        '  union {
                                        '    struct {
    ProcessorNumber As Byte             '      UCHAR ProcessorNumber;
    Alignment As Byte                   '      UCHAR Alignment;
                                        '    } DUMMYSTRUCTNAME;
                                        '    USHORT ProcessorIndex;
                                        '  } DUMMYUNIONNAME;
    LoggerId As Integer                 '  USHORT LoggerId;
End Type                                '} ETW_BUFFER_CONTEXT, *PETW_BUFFER_CONTEXT;

Public Type EVENT_RECORD                'typedef struct _EVENT_RECORD {
    EventHeader As EVENT_HEADER         '  EVENT_HEADER                     EventHeader;
    BufferContext As ETW_BUFFER_CONTEXT '  ETW_BUFFER_CONTEXT               BufferContext;
    ExtendedDataCount As Integer        '  USHORT                           ExtendedDataCount;
    UserDataLength As Integer           '  USHORT                           UserDataLength;
    ExtendedData As Long                '  PEVENT_HEADER_EXTENDED_DATA_ITEM ExtendedData;
    UserData As Long                    '  PVOID                            UserData;
    UserContext As Long                 '  PVOID                            UserContext;
End Type                                '} EVENT_RECORD, *PEVENT_RECORD;

Public Type EVENT_HEADER_EXTENDED_DATA_ITEM 'typedef struct _EVENT_HEADER_EXTENDED_DATA_ITEM {
    Reserved1 As Integer                '  USHORT    Reserved1;
    ExtType As Integer                  '  USHORT    ExtType;
                                        '  struct {
    Linkage As Integer                  '    USHORT Linkage : 1;
    Reserved2 As Integer                '    USHORT Reserved2 : 15;
                                        '  };
    DataSize As Integer                 '  USHORT    DataSize;
    DataPtr As Currency                 '  ULONGLONG DataPtr;
End Type                                '} EVENT_HEADER_EXTENDED_DATA_ITEM, *PEVENT_HEADER_EXTENDED_DATA_ITEM;


Public Const EVENT_MIN_LEVEL = (0)
'    Lowest value for an event level is 0. */
Public Const EVENT_MAX_LEVEL = (&HFF)
'    Highest value for an event level is 255. */

'/*
'EVENT_ACTIVITY_CTRL values for the ControlCode parameter of
'EventActivityIdControl.
'*/
Public Const EVENT_ACTIVITY_CTRL_GET_ID = (1)
'    EventActivityIdControl will return the current thread's activity ID. */
Public Const EVENT_ACTIVITY_CTRL_SET_ID = (2)
'    EventActivityIdControl will set the current thread's activity ID. */
Public Const EVENT_ACTIVITY_CTRL_CREATE_ID = (3)
'    EventActivityIdControl will generate and return a new activity ID. Note
'    that the returned activity ID is not a GUID. The EventActivityIdControl
'    function uses a faster generation algorithm than UuidCreate. The returned
'    ID is guaranteed to be different from any valid GUID and different from any
'    other activity ID generated by EventActivityIdControl on the same machine
'    during the same boot session. */
Public Const EVENT_ACTIVITY_CTRL_GET_SET_ID = (4)
'    EventActivityIdControl will set the current thread's activity ID and
'    return the previous activity ID. */
Public Const EVENT_ACTIVITY_CTRL_CREATE_SET_ID = (5)
'    EventActivityIdControl will generate a new activity ID, set the current
'    Thread 's activity ID to the new value, and return the previous activity
'    ID. */

Public Const MAX_EVENT_DATA_DESCRIPTORS = (128)
'    The maximum number of EVENT_DATA_DESCRIPTORs that can be used in an event.
'    Used with EventWrite, EventWriteTransfer, EventWriteEx. */
Public Const MAX_EVENT_FILTER_DATA_SIZE = (1024)
'    The maximum data size for many of the filter types.
'    Used with EVENT_FILTER_DESCRIPTOR. */
Public Const MAX_EVENT_FILTER_PAYLOAD_SIZE = (4096)
'    The maximum data size for an event payload filter.
'    Used with EVENT_FILTER_DESCRIPTOR of type EVENT_FILTER_TYPE_PAYLOAD. */
Public Const MAX_EVENT_FILTER_EVENT_NAME_SIZE = (4096)
'    The maximum data size for a name-based filter.
'    Used with EVENT_FILTER_DESCRIPTOR for name-based filters. */

Public Const MAX_EVENT_FILTERS_COUNT = (13)
'    The maximum number of filters that can be provided in a call to
'    EnableTraceEx2.
'    Used with ENABLE_TRACE_PARAMETERS. */

Public Const MAX_EVENT_FILTER_PID_COUNT = (8)
'    The maximum number of process IDs in a PID filter.
'    Used with EVENT_FILTER_DESCRIPTOR of type EVENT_FILTER_TYPE_PID. */

Public Const MAX_EVENT_FILTER_EVENT_ID_COUNT = (64)
'    The maximum number of event IDs in an event ID or stackwalk filter.
'    Used with EVENT_FILTER_DESCRIPTOR of type EVENT_FILTER_TYPE_EVENT_ID or
'    EVENT_FILTER_TYPE_STACKWALK. */
Public Enum EventFilterType
    EVENT_FILTER_TYPE_NONE = (&H0)
    EVENT_FILTER_TYPE_SCHEMATIZED = (&H80000000)   ' Provider-side.
    EVENT_FILTER_TYPE_SYSTEM_FLAGS = (&H80000001)   ' Internal use only.
    EVENT_FILTER_TYPE_TRACEHANDLE = (&H80000002)   ' Initiate rundown.
    EVENT_FILTER_TYPE_PID = (&H80000004)   ' Process ID.
    EVENT_FILTER_TYPE_EXECUTABLE_NAME = (&H80000008)   ' EXE file name.
    EVENT_FILTER_TYPE_PACKAGE_ID = (&H80000010)   ' Package ID.
    EVENT_FILTER_TYPE_PACKAGE_APP_ID = (&H80000020)   ' Package Relative App Id (PRAID).
    EVENT_FILTER_TYPE_PAYLOAD = (&H80000100)   ' TDH payload filter.
    EVENT_FILTER_TYPE_EVENT_ID = (&H80000200)   ' Event IDs.
    EVENT_FILTER_TYPE_EVENT_NAME = (&H80000400)   ' Event name (TraceLogging only).
    EVENT_FILTER_TYPE_STACKWALK = (&H80001000)   ' Event IDs for stack.
    EVENT_FILTER_TYPE_STACKWALK_NAME = (&H80002000)   ' Event name for stack (TraceLogging only).
    EVENT_FILTER_TYPE_STACKWALK_LEVEL_KW = (&H80004000)   ' Filter stack collection by level and keyword.
End Enum

Public Type EVENT_FILTER_HEADER             'typedef struct _EVENT_FILTER_HEADER {
    id As Integer                           '    USHORT     Id;
    Version As Byte                         '    UCHAR      Version;
    Reserved(0 To 4) As Byte                '    UCHAR      Reserved[5];
    InstanceId As Currency                  '    ULONGLONG  InstanceId;
    Size As Long                            '    ULONG      Size;
    NextOffset As Long                      '    ULONG      NextOffset;
End Type                                    '} EVENT_FILTER_HEADER, *PEVENT_FILTER_HEADER;
                                            '
Public Type EVENT_FILTER_EVENT_ID           'typedef struct _EVENT_FILTER_EVENT_ID {
    FilterIn As Byte                        '    BOOLEAN FilterIn;
    Reserved As Byte                        '    UCHAR Reserved;
    Count As Integer                        '    USHORT Count;
    Events(0 To 0) As Integer               '    USHORT Events[ANYSIZE_ARRAY];
End Type                                    '} EVENT_FILTER_EVENT_ID, *PEVENT_FILTER_EVENT_ID;



Public Declare Function CloseTrace Lib "advapi32" (ByVal TraceHandle As Currency) As Long
Public Declare Function ControlTraceW Lib "advapi32" (ByVal TraceHandle As Currency, ByVal InstanceName As Long, Properties As Any, ByVal ControlCode As ControlTraceCodes) As Long
Public Declare Function EnableTrace Lib "advapi32" (ByVal Enable As Long, ByVal EnableFlag As Long, ByVal EnableLevel As Long, ControlGuid As GUID, ByVal TraceHandle As Currency) As Long
Public Declare Function EnableTraceEx Lib "advapi32" (ProviderId As GUID, SourceId As GUID, ByVal TraceHandle As Currency, ByVal IsEnabled As Long, ByVal Level As Byte, ByVal MatchAnyKeyWord As Currency, ByVal MatchAllKeyword As Currency, ByVal EnableProperty As Long, EnableFilterDesc As EVENT_FILTER_DESCRIPTOR) As Long
Public Declare Function EnableTraceEx2 Lib "advapi32" (ByVal TraceHandle As Currency, ProviderId As GUID, ByVal ControlCode As EventControlCodes, _
                            ByVal Level As Byte, ByVal MatchAnyKeyWord As Currency, ByVal MatchAllKeyword As Currency, _
                            ByVal TimeOut As Long, EnableParameters As ENABLE_TRACE_PARAMETERS) As Long
Public Declare Function FlushTraceW Lib "advapi32" (ByVal TraceHandle As Currency, ByVal InstanceName As Long, Properties As EVENT_TRACE_PROPERTIES) As Long
Public Declare Function GetTraceEnableFlags Lib "advapi32" (ByVal TraceHandle As Currency) As Long
Public Declare Function GetTraceEnableLevel Lib "advapi32" (ByVal TraceHandle As Currency) As Long
Public Declare Function GetTraceLoggerHandle Lib "advapi32" (Buffer As Any) As Currency
Public Declare Function OpenTraceW Lib "advapi32" (logfile As EVENT_TRACE_LOGFILEW) As Currency
Public Declare Function ProcessTrace Lib "advapi32" (ByVal HandleArray As Long, ByVal HandleCount As Long, ByVal pStartTime As Long, ByVal pEndTime As Long) As Long 'pStart(End)Time are pointers to SYSTEMTIME structures, if you wanted to use them.
Public Declare Function QueryTraceW Lib "advapi32" (ByVal TraceHandle As Currency, ByVal InstanceName As Long, Properties As EVENT_TRACE_PROPERTIES) As Long
Public Declare Function RemoveTraceCallback Lib "advapi32" (pGuid As GUID) As Long
Public Declare Function SetTraceCallback Lib "advapi32" (pGuid As GUID, ByVal EventCallback As Long) As Long
Public Declare Function StartTraceW Lib "advapi32" (TraceHandle As Currency, ByVal InstanceName As Long, Properties As Any) As Long
Public Declare Function StopTraceW Lib "advapi32" (ByVal TraceHandle As Currency, ByVal InstanceName As Long, Properties As EVENT_TRACE_PROPERTIES) As Long
Public Declare Function TraceEvent Lib "advapi32" (ByVal TraceHandle As Currency, EventTrace As EVENT_TRACE_HEADER) As Long
Public Declare Function TraceEventInstance Lib "advapi32" (ByVal TraceHandle As Currency, EventTrace As EVENT_TRACE_HEADER, InstInfo As EVENT_INSTANCE_INFO, ParentInstInfo As EVENT_INSTANCE_INFO) As Long
Public Declare Function TraceMessage Lib "advapi32" (ByVal TraceHandle As Currency, ByVal MessageFlags As Long, MessageGuid As GUID, ByVal MessageNumber As Integer) As Long
Public Declare Function TraceQueryInformation Lib "advapi32" (ByVal SessionHandle As Currency, ByVal InformationClass As TRACE_QUERY_INFO_CLASS, TraceInformation As Long, ByVal InformationLength As Long, ReturnLength As Long) As Long
Public Declare Function TraceSetInformation Lib "advapi32" (ByVal SessionHandle As Currency, ByVal InformationClass As TRACE_QUERY_INFO_CLASS, TraceInformation As Any, ByVal InformationLength As Long) As Long
Public Declare Function UpdateTraceW Lib "advapi32" (ByVal TraceHandle As Currency, ByVal InstanceName As Long, Properties As EVENT_TRACE_PROPERTIES) As Long


Private Declare Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (Destination As Any, Source As Any, ByVal Length As Long)

'********************************
'MOF Structures
'Only those used by the current demo included; there's many more

Public Type DiskIo_TypeGroup1   'Class DiskIo_TypeGroup1: DiskIo {
     DiskNumber As Long         '  uint32 DiskNumber;
     IrpFlags As Long           '  uint32 IrpFlags;
     TransferSize As Long       '  uint32 TransferSize;
     Reserved As Long           '  uint32 Reserved;
     ByteOffset As Currency     '  sint64 ByteOffset;
     FileObject As Long         '  uint32 FileObject;
     IRP As Long                '  uint32 Irp;
     HighResResponseTime As Currency 'uint64 HighResResponseTime;
     IssuingThreadId As Long    '  uint32 IssuingThreadId;
End Type 'Event IDs: 10, 11, 55, 56'};
Public Type DiskIo_TypeGroup1_64   'Class DiskIo_TypeGroup1: DiskIo {
     DiskNumber As Long         '  uint32 DiskNumber;
     IrpFlags As Long           '  uint32 IrpFlags;
     TransferSize As Long       '  uint32 TransferSize;
     Reserved As Long           '  uint32 Reserved;
     ByteOffset As Currency     '  sint64 ByteOffset;
     FileObject As Currency     '  uint32 FileObject;
     IRP As Currency            '  uint32 Irp;
     HighResResponseTime As Currency 'uint64 HighResResponseTime;
     IssuingThreadId As Long    '  uint32 IssuingThreadId;
End Type 'Event IDs: 10, 11, 55, 56'};

Public Type DiskIo_TypeGroup2   'Class DiskIo_TypeGroup2: DiskIo {
      IRP As Long               '  uint32 Irp;
      IssuingThreadId As Long   '  uint32 IssuingThreadId;
End Type '12, 13, 15, 58, 59, 60'};
Public Type DiskIo_TypeGroup2_64   'Class DiskIo_TypeGroup2: DiskIo {
      IRP As Currency           '  uint32 Irp;
      IssuingThreadId As Long   '  uint32 IssuingThreadId;
End Type '12, 13, 15, 58, 59, 60'};

Public Type DiskIo_TypeGroup3   'Class DiskIo_TypeGroup3: DiskIo {
    DiskNumber As Long          '  uint32 DiskNumber;
    IrpFlags As Long            '  uint32 IrpFlags;
    HighResResponseTime As Currency 'uint64 HighResResponseTime;
    IRP As Long                 '  uint32 Irp;
    IssuingThreadId As Long     '  uint32 IssuingThreadId;
End Type '14, 57                '};
Public Type DiskIo_TypeGroup3_64 'Class DiskIo_TypeGroup3: DiskIo {
    DiskNumber As Long          '  uint32 DiskNumber;
    IrpFlags As Long            '  uint32 IrpFlags;
    HighResResponseTime As Currency 'uint64 HighResResponseTime;
    IRP As Currency             '  uint32 Irp;
    IssuingThreadId As Long     '  uint32 IssuingThreadId;
End Type '14, 57                '};


Public Type SystemConfig_LogDisk       'Class SystemConfig_LogDisk: SystemConfig {
    StartOffset As Currency             '  uint64 StartOffset;
    PartitionSize As Currency           '  uint64 PartitionSize;
    DiskNumber As Long                  '  uint32 DiskNumber;
    Size As Long                        '  uint32 Size;
    DriveType As Long                   '  uint32 DriveType;
    DriveLetterString(0 To 3) As Integer ' char16 DriveLetterString[];
    Pad1 As Long                        '  uint32 Pad1;
    PartitionNumber As Long             '  uint32 PartitionNumber;
    SectorsPerCluster As Long           '  uint32 SectorsPerCluster;
    BytesPerSector As Long              '  uint32 BytesPerSector;
    Pad2 As Long                        '  uint32 Pad2;
    NumberOfFreeClusters As Currency    '  sint64 NumberOfFreeClusters;
    TotalNumberOfClusters As Currency   '  sint64 TotalNumberOfClusters;
    FileSystem(0 To 15) As Byte         '  char16 FileSystem;
    VolumeExt As Long                   '  uint32 VolumeExt;
    Pad3 As Long                        '  uint32 Pad3;
End Type                                '};

Public Type FileIo_Name 'Event IDs: 0, 32, 35, 36
    FileObject As Long
    FileName(MAX_PATH_DOS) As Integer
End Type
Public Type FileIo_Name64 'Event IDs: 0, 32, 35, 36
    FileObject As Currency
    FileName(MAX_PATH_DOS) As Integer  'We don't use fixed length strings because VB fills
                                   'those with spaces rather than null chars, which
                                   'translates to slower processing, and speed is
                                   'critical to not crashing with ETW.
End Type
Public Type FileIo_Name64Ex
    FileObject As Currency
    FileName As String
End Type

Public Type FileIo_Create 'Event IDs: 64
    IrpPtr As Long
    FileObject As Long
    ttid As Long
    CreateOptions As CreateOpts
    FileAttributes As FILE_ATTRIBUTES
    ShareAccess As Long
    OpenPath(MAX_PATH_DOS) As Integer
End Type
Public Type FileIo_Create64 'Event IDs: 64
    IrpPtr As Currency
    FileObject As Currency
    ttid As Long
    CreateOptions As CreateOpts
    FileAttributes As FILE_ATTRIBUTES
    ShareAccess As Long
    OpenPath(MAX_PATH_DOS) As Integer
End Type

Public Type FileIo_Create64Ex 'Event IDs: 64
    IrpPtr As Currency
    FileObject As Currency
    ttid As Long
    CreateOptions As CreateOpts
    FileAttributes As FILE_ATTRIBUTES
    ShareAccess As Long
    OpenPath As String
End Type

Public Type FileIo_V2_Create
    IrpPtr As Long
    ttid As Long
    FileObject As Long
    CreateOptions As Long
    FileAttributes As Long
    ShareAccess As Long
    OpenPath(MAX_PATH_DOS) As Integer
End Type

Public Type FileIo_SimpleOp 'Event IDs: 65, 66, 73
    IrpPtr As Long
    FileObject As Long
    FileKey As Long
    ttid As Long
End Type
Public Type FileIo_SimpleOp64 'Event IDs: 65, 66, 73
    IrpPtr As Currency
    FileObject As Currency
    FileKey As Currency
    ttid As Long
End Type

Public Type FileIo_ReadWrite 'Event IDs: 67, 68
    Offset As Currency
    IrpPtr As Long
    FileObject As Long
    FileKey As Long
    ttid As Long
    IoSize As Long
    IoFlags As Long
End Type
Public Type FileIo_V2_ReadWrite 'Event IDs: 67, 68
    Offset As Currency
    IrpPtr As Long
    ttid As Long
    FileObject As Long
    FileKey As Long
    IoSize As Long
    IoFlags As Long
End Type
Public Type FileIo_ReadWrite64 'Event IDs: 67, 68
    Offset As Currency
    IrpPtr As Currency
    FileObject As Currency
    FileKey As Currency
    ttid As Currency
    IoSize As Long
    IoFlags As Long
End Type
Public Type FileIo_V2_ReadWrite64 'Event IDs: 67, 68
    Offset As Currency
    IrpPtr As Currency
    ttid As Currency
    FileObject As Currency
    FileKey As Currency
    IoSize As Long
    IoFlags As Long
End Type

Public Type FileIo_Info 'Event IDs: 69, 70, 71, 74, 75
    IrpPtr As Long
    FileObject As Long
    FileKey As Long
    ExtraInfo As Long
    ttid As Long
    InfoClass As Long
End Type
Public Type FileIo_Info64 'Event IDs: 69, 70, 71, 74, 75
    IrpPtr As Currency
    FileObject As Currency
    FileKey As Currency
    ExtraInfo As Currency
    ttid As Long
    InfoClass As Long
End Type


Public Type FileIo_DirEnum 'Event IDs: 72, 77
    IrpPtr As Long
    FileObject As Long
    FileKey As Long
    ttid As Long
    Length As Long
    InfoClass As Long
    FileIndex As Long
    FileName(MAX_PATH_DOS) As Integer
End Type
Public Type FileIo_DirEnum64 'Event IDs: 72, 77
    IrpPtr As Currency
    FileObject As Currency
    FileKey As Currency
    ttid As Long
    Length As Long
    InfoClass As Long
    FileIndex As Long
    FileName(MAX_PATH_DOS) As Integer
End Type
Public Type FileIo_DirEnum64Ex 'Event IDs: 72, 77
    IrpPtr As Currency
    FileObject As Currency
    FileKey As Currency
    ttid As Long
    Length As Long
    InfoClass As Long
    FileIndex As Long
    FileName As String
End Type
Public Type FileIo_V2_DirEnum64
    IrpPtr As Currency
    ttid As Currency
    FileObject As Currency
    FileKey As Currency
    Length As Long
    InfoClass As Long
    FileIndex As Long
    FileName(MAX_PATH_DOS) As Integer
End Type

Public Type FileIo_OpEnd 'Event IDs: 76
    IrpPtr As Long
    ExtraInfo As Long
    NtStatus As Long
End Type
Public Type FileIo_OpEnd64 'Event IDs: 76
    IrpPtr As Currency
    ExtraInfo As Currency
    NtStatus As Long
End Type

'=============
'UNDOCUMENTED
Public Type FileIo_PathOperation 'Event IDs: 79, 80, 81
    IrpPtr As Long
    FileObject As Long
    FileKey As Long
    ExtraInfo As Long
    ttid As Long
    InfoClass As Long
    FileName(MAX_PATH_DOS) As Integer
End Type
Public Type FileIo_PathOperation64 'Event IDs: 79, 80, 81
    IrpPtr As Currency
    FileObject As Currency
    FileKey As Currency
    ExtraInfo As Currency
    ttid As Long
    InfoClass As Long
    FileName(MAX_PATH_DOS) As Integer
End Type
Public Type FileIo_PathOperation64Ex 'Event IDs: 79, 80, 81
    IrpPtr As Currency
    FileObject As Currency
    FileKey As Currency
    ExtraInfo As Currency
    ttid As Long
    InfoClass As Long
    FileName As String
End Type
Public Type FileIo_V2_MapFile 'Event IDs 37, 38, 39, 40
    ViewBase As Long
    FileObject As Long
    MiscInfo As Currency
    ViewSize As Long
    ProcessID As Long
End Type
Public Type FileIo_V2_MapFile64 'Event IDs 37, 38, 39, 40
    ViewBase As Currency
    FileObject As Currency
    MiscInfo As Currency
    ViewSize As Currency
    ProcessID As Long
End Type
'End Undocumented
'=================

Public Type Thread_CSwitch
    NewThreadId As Long
    OldThreadId As Long
    NewThreadPriority As Byte
    OldThreadPriority As Byte
    PreviousCState As Byte
    SpareByte As Byte
    OldThreadWaitReason As Byte
    OldThreadWaitMode As Byte
    OldThreadState As Byte
    OldThreadWaitIdealProcessor As Byte
    NewThreadWaitTime As Long
    Reserved As Long
    'V4 additions--order???
'    Flags As Long 'type is guess
    ThreadFlags As Long 'Type is guess
        
End Type
Public Type Process_TypeGroup1_64Ex
    UniqueProcessKey As Currency
    ProcessID As Long
    ParentID As Long
    SessionID As Long
    ExitStatus As Long
    DirectoryTableBase As Currency
    UserSID As String
    ImageFileName As String
    CommandLine As String
End Type
Public Type Process_TypeGroup1_32Ex
    UniqueProcessKey As Long
    ProcessID As Long
    ParentID As Long
    SessionID As Long
    ExitStatus As Long
    DirectoryTableBase As Long
    UserSID As String
    ImageFileName As String
    CommandLine As String
End Type
Public Type FltIoInit
    RoutineAddr As Long
    FileObject As Long
    FileContext As Long
    IrpPtr As Long
    CallbackDataPtr As Long
    MajorFunction As Long
End Type
Public Type FltIoCompletion
    InitialTime As Long 'Object
    RoutineAddr As Long
    FileObject As Long
    FileContext As Long
    IrpPtr As Long
    CallbackDataPtr As Long
    MajorFunction As Long
End Type
Public Type FltIoFailure
    RoutineAddr As Long
    FileObject As Long
    FileContext As Long
    IrpPtr As Long
    CallbackDataPtr As Long
    MajorFunction As Long
    status As Long
End Type
Public Type TcpIp_TypeGroup1
    pid As Long
    Size As Long
    daddr As Long
    saddr As Long
    dport As Integer
    sport As Integer
    seqnum As Long
    connid As Long
End Type '28
Public Type TcpIp_TypeGroup2
    pid As Long
    Size As Long
    daddr As Long
    saddr As Long
    dport As Integer
    sport As Integer
    mss As Integer
    sackopt As Integer
    tsopt As Integer
    wsopt As Integer
    rcvwin As Long
    rcvwinscale As Integer
    seqnum As Long
    connid As Long
End Type


'Custom event consts:
Public Const ettCswitch As Byte = 36

Public Const ettfioName As Byte = 0
Public Const ettfioCreate As Byte = 32
Public Const ettfioDelete As Byte = 35
Public Const ettfioRundown As Byte = 36
Public Const ettfioCreate2 As Byte = 64
Public Const ettfioDirEnum As Byte = 72
Public Const ettfioDirNotify As Byte = 77
Public Const ettfioSetInfo As Byte = 69
Public Const ettfioDelete2 As Byte = 70
Public Const ettfioRename As Byte = 71
Public Const ettfioQueryInfo As Byte = 74
Public Const ettfioFsctl As Byte = 75
Public Const ettfioRead As Byte = 67
Public Const ettfioWrite As Byte = 68
Public Const ettfioCleanup As Byte = 65
Public Const ettfioClose As Byte = 66
Public Const ettfioFlush As Byte = 73
Public Const ettfioOpEnd As Byte = 76
Public Const ettfioMapFileEvent As Byte = 37
Public Const ettfioViewBaseEvent As Byte = 38
Public Const ettfioMapFileDCStart As Byte = 39
Public Const ettfioMapFileDCEnd As Byte = 40
Public Const ettfioDletePath As Byte = 79
Public Const ettfioRenamePath As Byte = 80
Public Const ettfioSetLinkPath As Byte = 81
 
Public Sub DEFINE_GUID(Name As GUID, l As Long, w1 As Integer, w2 As Integer, B0 As Byte, b1 As Byte, b2 As Byte, B3 As Byte, b4 As Byte, b5 As Byte, b6 As Byte, b7 As Byte)
  With Name
    .Data1 = l
    .Data2 = w1
    .Data3 = w2
    .Data4(0) = B0
    .Data4(1) = b1
    .Data4(2) = b2
    .Data4(3) = B3
    .Data4(4) = b4
    .Data4(5) = b5
    .Data4(6) = b6
    .Data4(7) = b7
  End With
End Sub

Public Function SystemTraceControlGuid() As GUID
'{9e814aad-3204-11d2-9a82-006008a86939}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H9E814AAD, CInt(&H3204), CInt(&H11D2), &H9A, &H82, &H0, &H60, &H8, &HA8, &H69, &H39)
  SystemTraceControlGuid = iid
End Function
Public Function SystemConfigGuid() As GUID
'{01853a65-418f-4f36-aefc-dc0f1d2fd235}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H1853A65, CInt(&H418F), CInt(&H4F36), &HAE, &HFC, &HDC, &HF, &H1D, &H2F, &HD2, &H35)
  SystemConfigGuid = iid
End Function
Public Function DiskIoGuid() As GUID
'{3d6fa8d4-fe05-11d0-9dda-00c04fd7ba7c}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H3D6FA8D4, CInt(&HFE05), CInt(&H11D0), &H9D, &HDA, &H0, &HC0, &H4F, &HD7, &HBA, &H7C)
  DiskIoGuid = iid
End Function
Public Function FileIoGuid() As GUID
' 0x90cbdc39, 0x4a3e, 0x11d1, { 0x84, 0xf4, 0x00, 0x00, 0xf8, 0x04, 0x64, 0xe3
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H90CBDC39, CInt(&H4A3E), CInt(&H11D1), &H84, &HF4, &H0, &H0, &HF8, &H4, &H64, &HE3)
 FileIoGuid = iid
End Function
Public Function EventTraceGuid() As GUID
'{68fdd900-4a3e-11d1-84f4-0000f80464e3}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H68FDD900, CInt(&H4A3E), CInt(&H11D1), &H84, &HF4, &H0, &H0, &HF8, &H4, &H64, &HE3)
 EventTraceGuid = iid
End Function
Public Function EventTraceConfigGuid() As GUID
'{01853a65-418f-4f36-aefc-dc0f1d2fd235}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H1853A65, CInt(&H418F), CInt(&H4F36), &HAE, &HFC, &HDC, &HF, &H1D, &H2F, &HD2, &H35)
 EventTraceConfigGuid = iid
End Function
Public Function DefaultTraceSecurityGuid() As GUID
'{0811c1af-7a07-4a06-82ed-869455cdf713}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H811C1AF, CInt(&H7A07), CInt(&H4A06), &H82, &HED, &H86, &H94, &H55, &HCD, &HF7, &H13)
  DefaultTraceSecurityGuid = iid
End Function
Public Function PrivateLoggerNotificationGuid() As GUID
'{3595ab5c-042a-4c8e-b942-2d059bfeb1b1}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H3595AB5C, CInt(&H42A), CInt(&H4C8E), &HB9, &H42, &H2D, &H5, &H9B, &HFE, &HB1, &HB1)
  PrivateLoggerNotificationGuid = iid
End Function
Public Function PerfInfoGuid() As GUID
'0xce1dbfb4, 0x137e, 0x4da6, { 0x87, 0xb0, 0x3f, 0x59, 0xaa, 0x10, 0x2c, 0xbc }
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &HCE1DBFB4, CInt(&H137E), CInt(&H4DA6), &H87, &HB0, &H3F, &H59, &HAA, &O10, &H2C, &HBC)
 PerfInfoGuid = iid
End Function
Public Function TcpIpGuid() As GUID
'{9a280ac0-c8e0-11d1-84e2-00c04fb998a2}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H9A280AC0, CInt(&HC8E0), CInt(&H11D1), &H84, &HE2, &H0, &HC0, &H4F, &HB9, &H98, &HA2)
  TcpIpGuid = iid
End Function
Public Function SplitIoGuid() As GUID
'{d837ca92-12b9-44a5-ad6a-3a65b3578aa8}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &HD837CA92, CInt(&H12B9), CInt(&H44A5), &HAD, &H6A, &H3A, &H65, &HB3, &H57, &H8A, &HA8)
  SplitIoGuid = iid
End Function
Public Function RegistryGuid() As GUID
'{ae53722e-c863-11d2-8659-00c04fa321a1}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &HAE53722E, CInt(&HC863), CInt(&H11D2), &H86, &H59, &H0, &HC0, &H4F, &HA3, &H21, &HA1)
  RegistryGuid = iid
End Function
Public Function ThreadGuid() As GUID
'{3d6fa8d1-fe05-11d0-9dda-00c04fd7ba7c}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H3D6FA8D1, CInt(&HFE05), CInt(&H11D0), &H9D, &HDA, &H0, &HC0, &H4F, &HD7, &HBA, &H7C)
 ThreadGuid = iid
End Function
Public Function ALPCGuid() As GUID
'{45d8cccd-539f-4b72-a8b7-5c683142609a}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H45D8CCCD, CInt(&H539F), CInt(&H4B72), &HA8, &HB7, &H5C, &H68, &H31, &H42, &H60, &H9A)
 ALPCGuid = iid
End Function
Public Function HWConfigGuid() As GUID
'{01853a65-418f-4f36-aefc-dc0f1d2fd235}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H1853A65, CInt(&H418F), CInt(&H4F36), &HAE, &HFC, &HDC, &HF, &H1D, &H2F, &HD2, &H35)
 HWConfigGuid = iid
End Function
Public Function ImageGuid() As GUID
'{2cb15d1d-5fc1-11d2-abe1-00a0c911f518}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H2CB15D1D, CInt(&H5FC1), CInt(&H11D2), &HAB, &HE1, &H0, &HA0, &HC9, &H11, &HF5, &H18)
 ImageGuid = iid
End Function
Public Function LostEventGuid() As GUID
'{6a399ae0-4bc6-4de9-870b-3657f8947e7e}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H6A399AE0, CInt(&H4BC6), CInt(&H4DE9), &H87, &HB, &H36, &H57, &HF8, &H94, &H7E, &H7E)
 LostEventGuid = iid
End Function
Public Function ObTraceGuid() As GUID
'{89497f50-effe-4440-8cf2-ce6b1cdcaca7}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H89497F50, CInt(&HEFFE), CInt(&H4440), &H8C, &HF2, &HCE, &H6B, &H1C, &HDC, &HAC, &HA7)
 ObTraceGuid = iid
End Function
Public Function PageFaultGuid() As GUID
'{3d6fa8d3-fe05-11d0-9dda-00c04fd7ba7c}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H3D6FA8D3, CInt(&HFE05), CInt(&H11D0), &H9D, &HDA, &H0, &HC0, &H4F, &HD7, &HBA, &H7C)
 PageFaultGuid = iid
End Function
Public Function ProcessGuid() As GUID
'{3d6fa8d0-fe05-11d0-9dda-00c04fd7ba7c}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H3D6FA8D0, CInt(&HFE05), CInt(&H11D0), &H9D, &HDA, &H0, &HC0, &H4F, &HD7, &HBA, &H7C)
 ProcessGuid = iid
End Function
Public Function StackWalkGuid() As GUID
'{def2fe46-7bd6-4b80-bd94-f57fe20d0ce3}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &HDEF2FE46, CInt(&H7BD6), CInt(&H4B80), &HBD, &H94, &HF5, &H7F, &HE2, &HD, &HC, &HE3)
 StackWalkGuid = iid
End Function
Public Function UdpIpGuid() As GUID
'{bf3a50c5-a9c9-4988-a005-2df0b7c80f80}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &HBF3A50C5, CInt(&HA9C9), CInt(&H4988), &HA0, &H5, &H2D, &HF0, &HB7, &HC8, &HF, &H80)
 UdpIpGuid = iid
End Function
Public Function KernelRundownGuid() As GUID
'{3b9c9951-3480-4220-9377-9c8e5184f5cd}
Static iid As GUID                            '0x3b9c9951,      0x3480,       0x4220, {0x93, 0x77, 0x9c, 0x8e, 0x51, 0x84, 0xf5, 0xcd
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &H3B9C9951, CInt(&H3480), CInt(&H4220), &H93, &H77, &H9C, &H8E, &H51, &H84, &HF5, &HCD)
  KernelRundownGuid = iid
End Function


'A custom one for this application for use with the newer multi-use kernel logger.
'It doesn't have to be registered anywhere, just unique, which GUIDGEN ensures.
Public Function VBKernelLoggerGuid() As GUID
'{CA596708-4C61-4413-A500-2760DAB4EF5A}
Static iid As GUID
 If (iid.Data1 = 0) Then Call DEFINE_GUID(iid, &HCA596708, CInt(&H4C61), CInt(&H4413), &HA5, &H0, &H27, &H60, &HDA, &HB4, &HEF, &H5A)
  VBKernelLoggerGuid = iid
End Function

'Custom utility functions to convert MOF structures to VB-friendly types
'We're given: The total length of the data block, a pointer to the data block, and the knowledge of the structure
'Previously, I used an Integer array buffered to MAX_PATH_DOS (DOS device name version of MAX_PATH). But that
'would leave two options; greatly increase the buffer, or lack long path support. I wanted to support long paths,
'so this method has more overhead, but is still better than 65k byte buffers.
Public Sub Fill_FileIoName64(ptr As Long, cb As Long, pStruct As FileIo_Name64Ex)
Dim bstr() As Byte
ReDim bstr(cb - 11&) 'Length is: sizeof(fixed part of structure) - sizeof(nullchar)=2.

CopyMemory ByVal VarPtr(pStruct), ByVal ptr, 8& 'Copy the fixed part of the structure
CopyMemory bstr(0&), ByVal ptr + 8&, cb - 10& 'Copy the string, without the terminating null.

pStruct.FileName = bstr
End Sub

Public Sub Fill_FileIoCreate64(ptr As Long, cb As Long, pStruct As FileIo_Create64Ex)
Dim bstr() As Byte
ReDim bstr(cb - 35&)

CopyMemory ByVal VarPtr(pStruct), ByVal ptr, 32& 'Copy the fixed part of the structure
CopyMemory bstr(0&), ByVal ptr + 32&, cb - 34& 'Copy the string, without the terminating null.
pStruct.OpenPath = bstr
End Sub

Public Sub Fill_FileIoDirEnum64(ptr As Long, cb As Long, pStruct As FileIo_DirEnum64Ex)
'Dim bstr() As Byte

'If (cb Mod 2) Then
'    I honestly have no clue what's going on here. There's extra shit on the end.
'    i 've checked if there's a new MOF def, there's not, the struct is correct
'    but the data doesn't match. Make sure odd bytes don't fuck us.
    CopyMemory ByVal VarPtr(pStruct), ByVal ptr, 40& 'Copy the fixed part of the structure
    SysReAllocStringLen VarPtr(pStruct.FileName), ptr + 40&, lstrlenW(ByVal ptr + 40&)
'Else
'    ReDim bstr(cb - 43&)
'    CopyMemory ByVal VarPtr(pStruct), ByVal ptr, 40& 'Copy the fixed part of the structure
'    CopyMemory bstr(0&), ByVal ptr + 40&, cb - 42& 'Copy the string, without the terminating null.
'    pStruct.FileName = bstr
'End If

End Sub

Public Sub Fill_FileIoPathOperation64(ptr As Long, cb As Long, pStruct As FileIo_PathOperation64Ex)
Dim bstr() As Byte
ReDim bstr(cb - 43&)

CopyMemory ByVal VarPtr(pStruct), ByVal ptr, 40& 'Copy the fixed part of the structure
CopyMemory bstr(0&), ByVal ptr + 40&, cb - 42& 'Copy the string, without the terminating null.

pStruct.FileName = bstr
End Sub

Public Function dbg_FindStrOffset(bt() As Byte, Optional nStart As Long = 12&) As Long
'Locates offset of \De from \Device\HarddiskVolume...
Dim i As Long
dbg_FindStrOffset = -1&
For i = nStart To UBound(bt)
    If bt(i) = &H5C Then
        If i + 2 < UBound(bt) Then
            If bt(i + 2) = &H44 Then
                If i + 4 < UBound(bt) Then
                    If bt(i + 4) = &H65 Then
                        dbg_FindStrOffset = i
                        Exit Function
                    End If
                End If
            End If
        End If
    End If
Next i

End Function

Public Sub dbg_AnalyzeMofStructPO(ptr As Long, cb As Long, vz As Byte)
'Analyze FileIo_PathOperation
Dim bt() As Byte
ReDim bt(cb - 1&)

CopyMemory bt(0&), ByVal ptr, cb

Dim i As Long
Dim nOff As Long
Dim tid As Long
Dim ic As Long

nOff = dbg_FindStrOffset(bt, 19&)
CopyMemory tid, ByVal ptr + 32&, 4&
CopyMemory ic, ByVal ptr + 36&, 4&

If szmax < 150& Then
    PostLog "PathOperation v" & CStr(vz) & " cbFixed=" & nOff & ",ttid=" & tid & ",InfoClass=" & GetFileInfoClassStr(ic)
    szmax = szmax + 1&
End If

End Sub
Public Sub dbg_AnalyzeMofStructDE(ptr As Long, cb As Long, vz As Byte)
'Analyze FileIo_DirEnum
Dim bt() As Byte
ReDim bt(cb - 1&)

CopyMemory bt(0&), ByVal ptr, cb

Dim i As Long
Dim nOff As Long
Dim tid As Long
Dim ic As Long

nOff = dbg_FindStrOffset(bt, 25&)
CopyMemory tid, ByVal ptr + 24&, 4&
CopyMemory ic, ByVal ptr + 32&, 4&

If szmax < 150& Then
    PostLog "DirEnum v" & CStr(vz) & "cbFixed=" & nOff & ",ttid=" & tid & ",InfoClass=" & GetFileInfoClassStr(ic)
    szmax = szmax + 1&
End If

End Sub

Public Sub dbg_AnalyzeMofStructCR(ptr As Long, cb As Long, vz As Byte)
'Analyze FileIo_Create (64)
Dim bt() As Byte
ReDim bt(cb - 1&)

CopyMemory bt(0&), ByVal ptr, cb

Dim i As Long
Dim nOff As Long
Dim tid As Long
Dim ic As Long

nOff = dbg_FindStrOffset(bt, 20&)
CopyMemory tid, ByVal ptr + 8&, 4&

If szmax < 150& Then
    PostLog "Create v" & CStr(vz) & ", cbFixed=" & nOff & ",ttid=" & tid
    szmax = szmax + 1&
End If

End Sub


