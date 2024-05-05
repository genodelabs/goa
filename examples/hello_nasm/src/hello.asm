; --- [ .rodata ] --------------------------------------------------------------

section .rodata

hello_str db 'hello from asm', 0

; --- [ .text ] ----------------------------------------------------------------

section .text

extern _ZN6Genode3Log3logEv                   ; Genode::Log::log()
extern _ZN6Genode3Log8_acquireENS0_4TypeE     ; Genode::Log::_acquire(Genode::Log::Type)
extern _ZN6Genode5printERNS_6OutputEPKc       ; Genode::print(Genode::Output &, char const *)
extern _ZN6Genode3Log8_releaseEv              ; Genode::Log::_release()

global _ZN9Component9constructERN6Genode3EnvE ; Component::construct(Genode::Env &)

; void Component::construct(Genode::Env &)
_ZN9Component9constructERN6Genode3EnvE:
	; Genode::log("hello from asm")
	push    rbx
	call    _ZN6Genode3Log3logEv
	xor     esi, esi
	mov     rbx, rax
	mov     rdi, rax
	call    _ZN6Genode3Log8_acquireENS0_4TypeE
	mov     rdi, QWORD [rbx+0x20]
	lea     rsi, [rel hello_str]
	call    _ZN6Genode5printERNS_6OutputEPKc
	mov     rdi, rbx
	pop     rbx
	jmp     _ZN6Genode3Log8_releaseEv
