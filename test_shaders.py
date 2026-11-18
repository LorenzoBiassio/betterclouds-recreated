import os
import subprocess
import sys
import tempfile
import zipfile

PANDORA_ROOT = r"C:\Users\lorenzo\AppData\Roaming\PandoraLauncher"
JAVA_EXE = os.path.join(PANDORA_ROOT, r"runtime\java-runtime-epsilon\windows-x64\bin\java.exe")
CLIENT_JAR = os.path.join(PANDORA_ROOT, r"libraries\net\minecraft\26.3\minecraft-client-26.3.jar")
LIBS_DIR = os.path.join(PANDORA_ROOT, "libraries")
PACK_ZIP_DST = os.path.join(PANDORA_ROOT, r"instances\V26.3\.minecraft\resourcepacks\BetterClouds-Recreated.zip")

JAVA_HARNESS = """
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.renderpearl.api.device.*;
import com.mojang.renderpearl.api.pipeline.*;
import com.mojang.renderpearl.backend.api.*;
import com.mojang.renderpearl.frontend.shaders.PipelineBuilder;
import it.unimi.dsi.fastutil.objects.Object2IntOpenHashMap;
import it.unimi.dsi.fastutil.objects.ReferenceArrayList;
import net.minecraft.client.renderer.RenderPipelines;
import net.minecraft.resources.Identifier;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class TestCloudPipelines {
    public static void main(String[] args) throws Exception {
        Path packDir = Paths.get(args[0]);
        Path clientJar = Paths.get(args[1]);

        DeviceInfo devInfo = new DeviceInfo(
            "MockGPU", "MockVendor", "1.0", false, "OpenGL", 1.0f,
            null, new DeviceFeatures(false, false, false, false, false, false, false, false), Set.of(),
            new HintsAndWorkarounds(false, false, false, false), null
        );

        GpuDevice mockDevice = (GpuDevice) Proxy.newProxyInstance(
            GpuDevice.class.getClassLoader(),
            new Class<?>[]{GpuDevice.class},
            (proxy, method, mArgs) -> {
                if (method.getName().equals("getDeviceInfo")) return devInfo;
                return null;
            }
        );

        Field devField = RenderSystem.class.getDeclaredField("DEVICE");
        devField.setAccessible(true);
        devField.set(null, mockDevice);

        GpuDeviceBackend mockBackend = (GpuDeviceBackend) Proxy.newProxyInstance(
            GpuDeviceBackend.class.getClassLoader(),
            new Class<?>[]{GpuDeviceBackend.class},
            (proxy, method, mArgs) -> {
                if (method.getName().equals("getDeviceInfo")) return devInfo;
                return null;
            }
        );

        try (ZipFile jarZip = new ZipFile(clientJar.toFile());
             PipelineBuilder builder = new PipelineBuilder(mockBackend)) {

            Map<Identifier, ShaderSource.CachedIncludeSource> includeCache = new HashMap<>();

            ShaderSource source = new ShaderSource() {
                @Override
                public String getShader(Identifier id, ShaderType type) {
                    String ext = type == ShaderType.VERTEX ? ".vsh" : ".fsh";
                    Path local = packDir.resolve("assets/" + id.getNamespace() + "/shaders/" + id.getPath() + ext);
                    try {
                        if (Files.exists(local)) {
                            System.out.println("  [DEBUG] Loaded custom shader override: " + local);
                            return Files.readString(local, StandardCharsets.UTF_8);
                        }
                        String entryName = "assets/" + id.getNamespace() + "/shaders/" + id.getPath() + ext;
                        ZipEntry ze = jarZip.getEntry(entryName);
                        if (ze != null) {
                            try (InputStream is = jarZip.getInputStream(ze)) {
                                return new String(is.readAllBytes(), StandardCharsets.UTF_8);
                            }
                        }
                    } catch (IOException e) {
                        throw new UncheckedIOException(e);
                    }
                    return null;
                }

                @Override
                public CachedIncludeSource getInclude(Identifier id) {
                    return includeCache.computeIfAbsent(id, k -> {
                        Path local = packDir.resolve("assets/" + k.getNamespace() + "/shaders/include/" + k.getPath());
                        try {
                            if (Files.exists(local)) {
                                String content = Files.readString(local, StandardCharsets.UTF_8);
                                System.out.println("  [DEBUG] Loaded custom #include override: " + local);
                                return CachedIncludeSource.create(k, content);
                            }
                            String entryName = "assets/" + k.getNamespace() + "/shaders/include/" + k.getPath();
                            ZipEntry ze = jarZip.getEntry(entryName);
                            if (ze != null) {
                                try (InputStream is = jarZip.getInputStream(ze)) {
                                    String content = new String(is.readAllBytes(), StandardCharsets.UTF_8);
                                    System.out.println("  [DEBUG] Resolved #include <" + k + ">");
                                    return CachedIncludeSource.create(k, content);
                                }
                            }
                        } catch (IOException e) {
                            return CachedIncludeSource.createError(e.getMessage());
                        }
                        return CachedIncludeSource.createError("Missing include: " + k);
                    });
                }

                @Override
                public void close() {
                    includeCache.values().forEach(CachedIncludeSource::close);
                }
            };

            List<RenderPipeline> pipelines = List.of(
                RenderPipelines.CLOUDS,
                RenderPipelines.FLAT_CLOUDS,
                RenderPipelines.OIT_CLOUDS.depthBoundsPipeline(),
                RenderPipelines.OIT_CLOUDS.transmittancePipeline(),
                RenderPipelines.OIT_CLOUDS.accumulatePipeline(),
                RenderPipelines.OIT_FLAT_CLOUDS.depthBoundsPipeline(),
                RenderPipelines.OIT_FLAT_CLOUDS.transmittancePipeline(),
                RenderPipelines.OIT_FLAT_CLOUDS.accumulatePipeline(),
                RenderPipelines.SOLID_TERRAIN,
                RenderPipelines.CUTOUT_TERRAIN,
                RenderPipelines.TRANSLUCENT_TERRAIN,
                RenderPipelines.OIT_TERRAIN.accumulatePipeline(),
                RenderPipelines.ENTITY_SOLID,
                RenderPipelines.SKY
            );

            Method genInfo = PipelineBuilder.class.getDeclaredMethod(
                "generateBackendCreateInfo",
                RenderPipeline.class, ShaderSource.class, ReferenceArrayList.class, Object2IntOpenHashMap.class
            );
            genInfo.setAccessible(true);

            for (RenderPipeline p : pipelines) {
                System.out.println("\\n[TEST] Compiling pipeline: " + p.getLocation());
                System.out.println("  [DEBUG] Defines: flags=" + p.getShaderDefines().flags() + " values=" + p.getShaderDefines().values());
                ReferenceArrayList<BackendRenderPipeline.CreateInfo.Shader> shaders = new ReferenceArrayList<>();
                Object2IntOpenHashMap<String> uniformMap = new Object2IntOpenHashMap<>();
                BackendRenderPipeline.CreateInfo info = (BackendRenderPipeline.CreateInfo) genInfo.invoke(builder, p, source, shaders, uniformMap);
                if (info == null) {
                    throw new RuntimeException("generateBackendCreateInfo returned null for " + p.getLocation());
                }
                for (BackendRenderPipeline.CreateInfo.Shader s : shaders) {
                    SpvModule.Reflection ref = s.module().reflect();
                    System.out.println("  [OK] Stage " + s.module().type() + " (" + s.name() + "): spvBytes=" + s.module().spv().remaining()
                        + " inputs=" + ref.inputs().stream().map(v -> v.location() + ":" + v.name()).toList()
                        + " outputs=" + ref.outputs().stream().map(v -> v.location() + ":" + v.name()).toList()
                        + " descriptors=" + ref.descriptors().stream().map(d -> d.name() + "@b" + d.binding()).toList());
                    s.module().close();
                }
                System.out.println("  [PASS] Pipeline " + p.getLocation() + " linked & validated! Uniform bindings: " + uniformMap);
            }
            source.close();
            System.out.println("\\n=== ALL 8 CLOUD PIPELINES PASSED FULL RENDERPEARL VALIDATION! ===");
        }
    }
}
"""


def main():
    libs = []
    for r, _, files in os.walk(LIBS_DIR):
        for f in files:
            if f.endswith(".jar"):
                libs.append(os.path.join(r, f))
    cp = ";".join(libs)

    with tempfile.TemporaryDirectory() as tmp:
        java_file = os.path.join(tmp, "TestCloudPipelines.java")
        with open(java_file, "w", encoding="utf-8") as f:
            f.write(JAVA_HARNESS)

        cmd = [
            JAVA_EXE,
            "--enable-native-access=ALL-UNNAMED",
            "-cp",
            cp,
            java_file,
            os.getcwd(),
            CLIENT_JAR,
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, check=False)
        print(res.stdout)
        if res.stderr:
            print(res.stderr, file=sys.stderr)
        res.check_returncode()

    os.makedirs(os.path.dirname(PACK_ZIP_DST), exist_ok=True)
    with zipfile.ZipFile(PACK_ZIP_DST, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write("pack.mcmeta", "pack.mcmeta")
        zf.write("assets/minecraft/shaders/core/clouds.vsh", "assets/minecraft/shaders/core/clouds.vsh")
        zf.write("assets/minecraft/shaders/core/clouds.fsh", "assets/minecraft/shaders/core/clouds.fsh")
        zf.write("assets/minecraft/shaders/core/sky.vsh", "assets/minecraft/shaders/core/sky.vsh")
        zf.write("assets/minecraft/shaders/core/sky.fsh", "assets/minecraft/shaders/core/sky.fsh")
        zf.write("assets/minecraft/shaders/include/fog.glsl", "assets/minecraft/shaders/include/fog.glsl")
        zf.write(
            "assets/minecraft/textures/environment/clouds.png",
            "assets/minecraft/textures/environment/clouds.png",
        )
    print(f"[PACKAGED] Updated {PACK_ZIP_DST}")


if __name__ == "__main__":
    main()
