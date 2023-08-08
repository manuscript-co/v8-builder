const std = @import("std");
const Builder = @import("std").build.Builder;
const join = std.fs.path.join;

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const toolchain = b.option([]const u8, "v8-toolchain", "toolchain to build v8");
    const CC = b.option([]const u8, "CC", "cc for staging");
    const CXX = b.option([]const u8, "CXX", "cxx for staging");

    const options: StagePrepOptions = .{ 
        .target = target, 
        .optimize = optimize, 
        .toolchain = toolchain, 
        .CC = CC, .CXX = CXX 
    };

    const a = makeV8Stage(b, options);
    b.getInstallStep().dependOn(a);
}

inline fn safeUnwrap(v: ?bool) bool {
    if (v) |vu| {
        if (vu) return true;
    }
    return false;
}

const StagePrepOptions = struct {
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
    toolchain: ?[]const u8,
    CC: ?[]const u8,
    CXX: ?[]const u8,
};

// assemble release tarball
fn prepRelease(b: *Builder) !*std.build.Step {
    const rel = b.step("release-tarball", "");
    const f = b.addSystemCommand(&.{ "echo", "'mrt'" });
    rel.dependOn(&f.step);
    return rel;
}

fn rp(b: *Builder, parts: []const []const u8) ![]const u8 {
    const joined = try join(b.allocator, parts);
    if (std.fs.path.isAbsolute(joined)) return joined;
    return std.build.FileSource.relative(joined).getPath(b.getInstallStep().owner);
}

fn lp(b: *Builder, parts: []const []const u8) !std.Build.LazyPath {
    const joined = try join(b.allocator, parts);
    return std.build.FileSource.relative(joined);
}

fn collapse(b: *Builder, s: []const u8) ![]const u8 {
    const out = try b.allocator.alloc(u8, s.len);
    _ = std.mem.replace(u8, s, "\n", " ", out);
    return out;
}

fn escapeDouble(b: *Builder, s: []const u8) ![]const u8 {
    const out = try b.allocator.alloc(u8, std.mem.replacementSize(u8, s, "\"", "\\\""));
    _ = std.mem.replace(u8, s, "\"", "\\\"", out);
    return out;
}

fn makeV8Stage(
    b: *Builder, 
    options: StagePrepOptions
) !*std.build.Step {
    std.debug.print("building v8", .{});
    const stagingDir = b.getInstallPath(.prefix, "staging");
    const v8 = b.step("v8", "build-v8");
    const v8src = try rp(b, &.{"deps", "v8"});
    const v8out = try rp(b, &.{stagingDir, "v8"});
    var gnargs = std.ArrayList([]const u8).init(b.allocator);
    defer gnargs.deinit();


    const basegn = 
    \\is_component_build=false
    \\v8_monolithic=true
    \\v8_use_external_startup_data=false
    \\v8_generate_external_defines_header=true
    \\v8_enable_31bit_smis_on_64bit_arch=true

    \\use_goma=false
    \\v8_enable_fast_mksnapshot=false
    \\v8_enable_snapshot_compression=true
    \\v8_enable_webassembly=false
    \\v8_enable_i18n_support=false
    
    \\cppgc_enable_young_generation=false
    \\cppgc_enable_caged_heap=false
    \\v8_enable_shared_ro_heap=false
    \\v8_enable_pointer_compression=false
    \\v8_enable_verify_heap=false
    \\v8_enable_sandbox=false

    \\use_custom_libcxx=false
    \\clang_use_chrome_plugins=false
    ;
    try gnargs.append(basegn);

    switch (options.target.getOsTag()) {
        .linux => {
            const linux = 
            \\v8_enable_private_mapping_fork_optimization=true
            \\clang_base_path="/usr"
            \\is_clang=false
            \\target_os="linux"
            \\host_os="linux"
            \\cc_wrapper="ccache"
            ;
            try gnargs.append(linux);
        },
        .macos => {
            const mac = 
            \\treat_warnings_as_errors=false
            \\use_lld=false
            \\use_gold=false
            \\target_os="mac"
            \\host_os="mac"
            \\cc_wrapper="ccache"
            ;
            if (options.toolchain) |chain| {
                try gnargs.append(b.fmt("clang_base_path=\"{s}\"", .{chain}));
            } else {
                try gnargs.append(b.fmt("clang_base_path=\"/usr\"", .{}));
            }
            try gnargs.append(mac);
        },
        else => unreachable
    }

    switch (options.target.getCpuArch()) {
        .arm, .aarch64 => {
            const arch = try collapse(b, 
            \\target_cpu="arm64"
            \\host_cpu="arm64"
        );
            try gnargs.append(arch);
        },
        .x86_64 => {
            try gnargs.append(try collapse(b, 
            \\target_cpu="x64"
            \\host_cpu="x64"
        ));},
        else => unreachable
    }

    if (options.optimize == .Debug) {
        const debug = 
        \\is_debug=true
        \\symbol_level=1
        \\v8_optimized_debug=true
        ;
        try gnargs.append(debug);
    }

    const gnbin = try rp(b, &.{"tools", "gn"});
    const gngen = b.addSystemCommand(&.{
        gnbin, "gen", 
        v8out,
        b.fmt("--args={s}", .{ try collapse(b, 
            try std.mem.join(b.allocator, " ", gnargs.items))}),
    });
    gngen.cwd = v8src;

    const ninja = b.addSystemCommand(&.{
        "ninja", "-j4", "v8_monolith"
    });
    ninja.cwd = v8out; 
    ninja.step.dependOn(&gngen.step);
    v8.dependOn(&ninja.step);
    return v8;
}

fn make101Stage(
    b: *Builder, 
    options: StagePrepOptions
) !*std.build.Step {
    const stagingDir = b.getInstallPath(.prefix, "staging");
    const o1 = b.step("101", "builds 101");
    const o1out = try rp(b, &.{stagingDir, "101"});
    const root = std.Build.FileSource.relative(".").getPath(b);
    const cwd = std.fs.cwd();
    cwd.access(o1out, .{ .mode = .read_only }) catch try cwd.makePath(o1out);
    
    // TODO support windows
    const cmake = b.addSystemCommand(&.{
        "cmake", root, "-G", "Ninja",
        b.fmt("-DCMAKE_CXX_FLAGS={s}", .{
            try std.mem.join(b.allocator, " ", &.{
                b.fmt("-I{s}", .{try rp(b, &.{stagingDir, "v8", "gen", "include"})}),
                try rp(b, &.{stagingDir, "v8", "obj", "libv8_monolith.a"})
            })
        }),
        if (options.optimize == .Debug) "-DCMAKE_BUILD_TYPE=Debug" else "-DCMAKE_BUILD_TYPE=Release",
    });

    if (options.CC) |CC| cmake.setEnvironmentVariable("CC", CC);
    if (options.CXX) |CXX| cmake.setEnvironmentVariable("CXX", CXX);

    const ninja = b.addSystemCommand(&.{
        "ninja", "-j4", "--quiet"
    });
    ninja.cwd = o1out;
    cmake.cwd = o1out;
    ninja.step.dependOn(&cmake.step);
    o1.dependOn(&ninja.step);
    return o1;
}
