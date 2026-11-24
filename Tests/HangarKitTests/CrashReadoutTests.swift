import Foundation
import Testing
@testable import HangarKit

private let logs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/WineLogs")

private func log(_ name: String) throws -> String {
    try String(contentsOf: logs.appending(path: name), encoding: .utf8)
}

// S-024
@Test func aMissingVisualCppDLLIsTheRuntimeNotAFile() throws {
    let reason = try #require(CrashReadout.reason(in: try log("missing-vcrun.log")))
    #expect(reason.kind == .missingRuntime(.visualCpp))
    #expect(reason.line.contains("MSVCP140.dll"))
    #expect(reason.title == "Missing Visual C++ 2022 runtime")
    #expect(reason.advice.contains("Microsoft Visual C++ 2015-2022 Redistributable"))
}

@Test func knownLinesMapToReasons() {
    func kind(_ line: String) -> CrashReason.Kind? { CrashReadout.reason(in: line)?.kind }
    #expect(kind(#"0024:err:module:import_dll Library d3dx9_43.dll (which is needed by L"C:\\G\\g.exe") not found"#) == .missingRuntime(.directX))
    #expect(kind(#"0024:err:module:import_dll Library XINPUT1_3.dll (which is needed by L"g.exe") not found"#) == .missingRuntime(.directX))
    #expect(kind(#"0024:err:module:import_dll Library VCRUNTIME140_1.dll (which is needed by L"g.exe") not found"#) == .missingRuntime(.visualCpp))
    #expect(kind(#"0024:err:module:import_dll Library steam_api64.dll (which is needed by L"g.exe") not found"#) == .missingFile("steam_api64.dll"))
    #expect(kind("0024:err:mscoree:CLRRuntimeInfo_GetRuntimeHost Wine Mono is not installed") == .missingRuntime(.dotNet))
    #expect(kind("0024:err:d3d12:D3D12CreateDevice D3D12CreateDevice failed, hr 0x887a0004") == .needsGraphics(.d3dMetal))
    #expect(kind("0024:err:virtual:map_view anonymous mmap() failed: out of memory") == .outOfMemory)
    #expect(kind("terminate called after throwing an instance of 'std::bad_alloc'") == .outOfMemory)
    #expect(kind("0024:fixme:ntdll:NtQuerySystemInformation info_class SYSTEM_PERFORMANCE_INFORMATION") == nil)
}

@Test func unsupportedDirect3D11FeaturesNeedDXVK() throws {
    #expect(CrashReadout.reason(in: try log("d3d11.log"))?.kind == .needsGraphics(.dxvk))
    #expect(CrashReadout.reason(in: try log("clean.log")) == nil)
}

@Test func wineLinesReadAsLogEntries() throws {
    let line = try #require(WineLog.parseLine(#"1712.032:0024:0028:err:module:import_dll Library MSVCP140.dll (which is needed by L"g.exe") not found"#))
    #expect(line.time == "1712.032")
    #expect(line.level == .error)
    #expect(line.source == "module")
    #expect(line.code == "import_dll")
    #expect(line.message.hasPrefix("Library MSVCP140.dll"))
    #expect(WineLog.parseLine("0024:fixme:ntdll:NtQuerySystemInformation info_class 2")?.level == .debug)
    #expect(WineLog.parseLine("Log started at Mon Nov 24 13:40:01 2026") == nil)
    let document = WineLog.parser.parse(try log("missing-vcrun.log"))
    #expect(document.entries.filter { $0.level == .error }.count == 3)
}

@Test func aBottleLaunchWritesCrossOversLog() {
    let plan = LaunchPlan(executable: URL(fileURLWithPath: "/X/wine"), arguments: ["--bottle", "Steam", "--no-wait", "--cx-app", "C:/g.exe"], processHints: [])
    let logged = plan.loggingWine(to: URL(fileURLWithPath: "/tmp/g.log"))
    #expect(logged.arguments == ["--cx-log", "/tmp/g.log", "--bottle", "Steam", "--no-wait", "--cx-app", "C:/g.exe"])
    #expect(logged.outputFile == nil)
}

@Test func aPrefixLaunchKeepsWineErrors() {
    var plan = LaunchPlan(executable: URL(fileURLWithPath: "/X/wine64"), arguments: ["C:/g.exe"], processHints: [])
    plan.environment = ["WINEPREFIX": "/P", "WINEDEBUG": "-all"]
    let logged = plan.loggingWine(to: URL(fileURLWithPath: "/tmp/g.log"))
    #expect(logged.environment["WINEDEBUG"] == "fixme-all")
    #expect(logged.outputFile?.path == "/tmp/g.log")
    // A Mac game has no Wine log.
    let mac = LaunchPlan(executable: URL(fileURLWithPath: "/usr/bin/open"), arguments: ["/A.app"], processHints: [])
    #expect(mac.loggingWine(to: URL(fileURLWithPath: "/tmp/g.log")) == mac)
}
