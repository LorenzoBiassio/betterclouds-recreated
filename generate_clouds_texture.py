import math
import struct
import zlib


def hash2(ix: int, iz: int, period: int, seed: int) -> tuple[float, float]:
    ix %= period
    iz %= period
    h = (ix * 374761393 + iz * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = (h ^ (h >> 16)) & 0xFFFFFFFF
    angle = (h / 4294967296.0) * (2.0 * math.pi)
    return math.cos(angle), math.sin(angle)


def grad_noise_tileable(x: float, z: float, period: int, seed: int) -> float:
    x0 = math.floor(x)
    z0 = math.floor(z)
    fx = x - x0
    fz = z - z0
    ux = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
    uz = fz * fz * fz * (fz * (fz * 6.0 - 15.0) + 10.0)

    def dot_grid(dx: int, dz: int) -> float:
        gx, gz = hash2(x0 + dx, z0 + dz, period, seed)
        return gx * (fx - dx) + gz * (fz - dz)

    n00 = dot_grid(0, 0)
    n10 = dot_grid(1, 0)
    n01 = dot_grid(0, 1)
    n11 = dot_grid(1, 1)
    nx0 = n00 + ux * (n10 - n00)
    nx1 = n01 + ux * (n11 - n01)
    return nx0 + uz * (nx1 - nx0)


def fbm_clouds(u: float, v: float) -> float:
    # Finer-scale multi-octave noise (16..64 periods per 256 cells)
    # so clouds form compact, frequent Better Clouds cumulus puffs rather than giant continents
    n1 = grad_noise_tileable(u * 14.0, v * 14.0, 14, 101) * 0.46
    n2 = grad_noise_tileable(u * 28.0, v * 28.0, 28, 202) * 0.32
    n3 = grad_noise_tileable(u * 56.0, v * 56.0, 56, 303) * 0.15
    n4 = grad_noise_tileable(u * 96.0, v * 96.0, 96, 404) * 0.07
    return (n1 + n2 + n3 + n4) * 0.5 + 0.5


def write_png(path: str, width: int, height: int, rgba_bytes: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw_rows = bytearray()
    stride = width * 4
    for y in range(height):
        raw_rows.append(0)
        raw_rows.extend(rgba_bytes[y * stride : (y + 1) * stride])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw_rows), level=9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main() -> None:
    width, height = 256, 256
    buf = bytearray(width * height * 4)

    active_cells = 0
    for z in range(height):
        for x in range(width):
            # Cardinal-isolated checkerboard lattice so every active cell has 0 N/S/E/W neighbors
            # and therefore CloudRenderer emits all 3 camera-facing 3D box faces for every cell.
            if (x + z) % 2 != 0:
                continue

            u = x / width
            v = z / height
            val = fbm_clouds(u, v)

            # Secondary detail for scattered small cumulus puffs between main clusters
            wisp = grad_noise_tileable(u * 48.0, v * 48.0, 48, 777) * 0.5 + 0.5

            is_cloud = (val > 0.515) or (val > 0.475 and wisp > 0.58)
            if is_cloud:
                idx = (z * width + x) * 4
                buf[idx + 0] = 255
                buf[idx + 1] = 255
                buf[idx + 2] = 255
                buf[idx + 3] = 255
                active_cells += 1

    out_path = "assets/minecraft/textures/environment/clouds.png"
    write_png(out_path, width, height, bytes(buf))
    total_checker = (width * height) // 2
    print(
        f"Generated {out_path} ({width}x{height}): {active_cells} active 3D puff cells ({active_cells / total_checker * 100:.1f}% cluster coverage)"
    )


if __name__ == "__main__":
    main()
