require "zlib"

# Hand-rolled zip writer so specs can build hostile archives rubyzip would refuse.
# entries: [{ name:, data:, method: :stored|:deflate, unix_mode: nil, flags: 0, declared_size: nil }]
module RawZip
  def self.build(entries)
    out = "".b
    central = "".b
    entries.each do |e|
      data = e.fetch(:data).b
      method = e.fetch(:method, :stored)
      body = method == :deflate ? raw_deflate(data) : data
      size = e[:declared_size] || data.bytesize
      name = e.fetch(:name).b
      flags = e.fetch(:flags, 0)
      code = method == :deflate ? 8 : (method.is_a?(Integer) ? method : 0)
      crc = Zlib.crc32(data)
      offset = out.bytesize
      out << [ 0x04034b50, 20, flags, code, 0, 0x21, crc, body.bytesize, size, name.bytesize, 0 ].pack("VvvvvvVVVvv") << name << body
      attr = e[:unix_mode] ? e[:unix_mode] << 16 : 0
      central << [ 0x02014b50, 3 << 8 | 20, 20, flags, code, 0, 0x21, crc, body.bytesize, size, name.bytesize, 0, 0, 0, 0, attr, offset ].pack("VvvvvvvVVVvvvvvVV") << name
    end
    cd_offset = out.bytesize
    out << central << [ 0x06054b50, 0, 0, entries.size, entries.size, central.bytesize, cd_offset, 0 ].pack("VvvvvVVv")
  end

  def self.raw_deflate(data)
    z = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    z.deflate(data, Zlib::FINISH).tap { z.close }
  end
end
