// Decompile a list of (address, size, name) ranges without full auto-analysis.
// Usage (Ghidra headless postScript):
//   DecompileRanges.java <output.txt> <targets.tsv>
// Each target line: 0xADDRESS<TAB>SIZE<TAB>NAME
// The script disassembles the range, creates a function, decompiles it, and
// resolves referenced DAT_/PTR_DAT_ constants into printable strings.

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.SourceType;

public class DecompileRanges extends GhidraScript {
    private static final Pattern DAT_PATTERN =
        Pattern.compile("\\b(?:DAT|PTR_DAT|PTR_PTR_DAT|s)_([0-9a-fA-F]{6,})\\b");

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            println("usage: DecompileRanges.java <output.txt> <targets.tsv>");
            return;
        }
        String outPath = args[0];
        String specPath = args[1];

        List<String[]> targets = new ArrayList<>();
        try (BufferedReader reader = new BufferedReader(new FileReader(specPath))) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] parts = line.split("\\t");
                if (parts.length >= 3) targets.add(parts);
            }
        }

        DecompInterface decompiler = new DecompInterface();
        DecompileOptions options = new DecompileOptions();
        decompiler.setOptions(options);
        if (!decompiler.openProgram(currentProgram)) {
            println("decompiler.openProgram failed");
            return;
        }

        Listing listing = currentProgram.getListing();
        Memory memory = currentProgram.getMemory();
        PrintWriter out = new PrintWriter(new FileWriter(outPath));

        for (String[] target : targets) {
            String addressText = target[0].trim();
            long addressValue = Long.decode(addressText);
            long size = Long.decode(target[1].trim());
            String name = target[2].trim();
            Address start = toAddr(addressValue);
            Address end = toAddr(addressValue + size - 1);

            out.println("================================================================================");
            out.println("=== " + name + " @ " + addressText + " size=" + size + " ===");
            out.println("================================================================================");

            try {
                AddressSet range = new AddressSet(start, end);
                new DisassembleCommand(range, null, true).applyTo(currentProgram, monitor);
                Function function = getFunctionAt(start);
                if (function == null) {
                    function = getFunctionContaining(start);
                    if (function != null) {
                        out.println("// using containing function " + function.getName()
                            + " @ " + function.getEntryPoint()
                            + " (requested " + addressText + ")");
                    }
                }
                if (function == null) {
                    function = createFunction(start, name);
                }
                if (function == null) {
                    for (int offset = 1; offset <= 4; offset++) {
                        Address candidate = start.add(offset);
                        new DisassembleCommand(candidate, null, true)
                            .applyTo(currentProgram, monitor);
                        function = getFunctionAt(candidate);
                        if (function == null) {
                            function = createFunction(candidate, name);
                        }
                        if (function != null) {
                            out.println("// function starts " + offset
                                + " byte(s) after symbol: " + candidate);
                            break;
                        }
                    }
                }
                if (function == null) {
                    out.println("!! createFunction failed");
                    Function containing = getFunctionContaining(start);
                    if (containing != null) {
                        out.println("// containing function: " + containing.getName()
                            + " @ " + containing.getEntryPoint());
                    }
                    out.println();
                    continue;
                }
                try {
                    function.setName(name, SourceType.USER_DEFINED);
                } catch (Exception ignored) {
                }
                try {
                    function.setBody(range);
                } catch (Exception ignored) {
                }
                DecompileResults results = decompiler.decompileFunction(function, 120, monitor);
                if (results == null || !results.decompileCompleted()) {
                    out.println("!! decompile failed: "
                        + (results == null ? "null" : results.getErrorMessage()));
                    out.println();
                    continue;
                }
                String code = results.getDecompiledFunction().getC();
                out.println(code);
                out.println();
                out.println("---- referenced printable constants ----");
                Map<String, String> constants = resolveConstants(code, memory);
                for (Map.Entry<String, String> entry : constants.entrySet()) {
                    out.println(entry.getKey() + " = " + entry.getValue());
                }
                out.println();
            } catch (Exception e) {
                out.println("!! exception: " + e);
                out.println();
            }
            out.flush();
        }

        out.close();
        decompiler.dispose();
        println("wrote " + outPath);
    }

    private Map<String, String> resolveConstants(String code, Memory memory) {
        Map<String, String> found = new TreeMap<>();
        Matcher matcher = DAT_PATTERN.matcher(code);
        while (matcher.find()) {
            String hex = matcher.group(1);
            if (found.containsKey(hex)) continue;
            try {
                Address address = toAddr(Long.parseLong(hex, 16));
                byte[] buffer = new byte[160];
                int read = memory.getBytes(address, buffer);
                if (read <= 0) continue;
                int length = 0;
                while (length < read) {
                    int value = buffer[length] & 0xff;
                    if (value == 0) break;
                    if (value < 0x20 && value != '\n' && value != '\t') break;
                    if (value == 0x7f) break;
                    length++;
                }
                if (length < 2) continue;
                String text = new String(buffer, 0, length, StandardCharsets.UTF_8);
                StringBuilder printable = new StringBuilder();
                for (int i = 0; i < text.length(); i++) {
                    char c = text.charAt(i);
                    if (c == '\n' || c == '\t' || (c >= 0x20 && c != 0x7f)) {
                        printable.append(c);
                    } else {
                        break;
                    }
                }
                if (printable.length() >= 2) {
                    found.put(hex, printable.toString());
                }
            } catch (Exception ignored) {
            }
        }
        return found;
    }
}
