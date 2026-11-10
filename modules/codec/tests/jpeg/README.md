These original constant-color JPEG images were initially encoded with Pillow for the JPEG decoder tests. They cover grayscale/RGB baseline and progressive streams and EXIF orientation. `silk task fixtures jpeg` regenerates the five header fixtures and embedded Silk vectors from the repository root, using native `cjpeg` (libjpeg/libjpeg-turbo) for independent encoding and Silk for EXIF and malformed marker assembly. Encoder versions may affect encoded bytes, so regeneration is intentional rather than part of the normal gate. The migration itself preserves the committed JPEG files and test vectors.

Header tests do not establish successful entropy decoding. Pixel-decoder tests will consume these same fixtures as that implementation is added.

`grayGradient.jpg` and `grayRestart.jpg` are additional original 17×9 grayscale pixel fixtures. The former exercises AC reconstruction; the latter has a restart interval of one MCU and five restart markers. Pixel expectations were obtained independently with Pillow; the tests allow one sample level for differing IDCT rounding.

`silk task fixtures jpeg-progressive` generates original 23×19 varying-pixel images
in grayscale and 4:4:4, 4:2:2 and 4:2:0 RGB, with and without restart markers.
Tests compare progressive reconstruction exactly against sequential encoding of
the same coefficients. This checks scan equivalence, not independent color or
IDCT accuracy; the separate pixel and IDCT tests cover those contracts. The
task also assembles a three-scan sequential constant image from T.81 marker
and Huffman syntax, and generates malformed progression/restart/truncation tests.

`silk task fixtures jpeg-metadata` inserts original APP1/APP2 segments to cover EXIF
coexisting with XMP, reordered ICC chunks, chunks between progressive scans and
invalid sequence framing. Its opaque profile payload tests byte transport only,
not ICC profile validity. `orientation_tests.silk` independently specifies all
eight exact pixel permutations of a labelled 3×2 image, including alpha channels.

The generators are actual Silk tasks in `tasks/codec_fixtures.silk` and
`tasks/fixtures_*.silk`; no Python, Pillow, JavaScript or shell interpreter is
invoked. JPEG encoding tasks require `cjpeg` on `PATH`, with `-progressive`,
`-sample`, and MCU-block `-restart NB` support. Metadata generation only needs
the committed `orientedRgb.jpg` and `progressiveGray.jpg`. Source-generating
tasks format their output with the Silk compiler that launched the task.

`silk task fixtures jpeg-benchmark OUTPUT` writes the original four untracked
512×384 workloads into the required output directory (created as needed).
The images are `L-baseline.jpg`, `L-progressive.jpg`, `RGB-baseline.jpg`, and
`RGB-progressive.jpg`, quality 90, with 4:2:0 RGB sampling. Relative output
directories resolve from the repository root; absolute paths are accepted.

`silk task fixtures png` regenerates the independent PNG sample, malformed-input
and metadata tests. Silk assembles PNG chunks, CRCs, all filters, Adam7 passes,
APNG frame sequences, transparency and ICC payloads. Native `gzip -n -c` on
`PATH` provides independent DEFLATE streams; Silk supplies the zlib framing
and Adler-32 checksum, without calling the codec's encoder. This retains the
16 MiB ICC inflation-limit regression as well as every truncation contract.
Temporary native encoder inputs are removed on success and failure.
