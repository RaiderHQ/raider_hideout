# Rack defaults to 128 file parts per request; a large suite with failures can exceed that.
Rack::Utils.multipart_file_limit = 2_000
