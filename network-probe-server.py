"""Loopback-only HTTP and DNS targets for testing the isolated QEMU guest."""
import http.server
import socket
import struct
import threading

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body=b"PS5_OPENWRT_FORWARDING_OK\n"
        self.send_response(200)
        self.send_header("Content-Length",str(len(body)))
        self.end_headers()
        self.wfile.write(body)

def dns():
    server=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    server.bind(("127.0.0.1",1053))
    while True:
        data,peer=server.recvfrom(4096)
        try:
            pos=12
            while data[pos]:pos+=data[pos]+1
            end=pos+5
            question=data[12:end]
            answer=b"\xc0\x0c"+struct.pack("!HHIH",1,1,60,4)+socket.inet_aton("93.184.216.34")
            response=data[:2]+b"\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00"+question+answer
            server.sendto(response,peer)
        except (IndexError,ValueError):
            continue

threading.Thread(target=dns,daemon=True).start()
http.server.HTTPServer(("127.0.0.1",18888),Handler).serve_forever()
