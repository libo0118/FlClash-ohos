//go:build openharmony && cgo

package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"core"
	"sync"
	"unsafe"

	"github.com/metacubex/mihomo/tunnel"
)

type tunCallbacks struct {
	callback unsafe.Pointer
}

func (c tunCallbacks) Protect(fd int) bool {
	protect(c.callback, fd)
	return true
}

func (c tunCallbacks) ResolveUid(protocol int, source, target string) int {
	return -1
}

func (c tunCallbacks) ResolvePackage(uid int) string {
	return ""
}

var bridgeMu sync.Mutex
var tunCallback unsafe.Pointer
var listenerCallback unsafe.Pointer

//export invokeMethod
func invokeMethod(callback unsafe.Pointer, data *C.char) {
	params := takeCString(data)
	core.InvokeMethod(params, func(result []byte) {
		invokeResult(callback, string(result))
		releaseObject(callback)
	})
}

//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, stack, address, dns, options *C.char) bool {
	stackValue, addressValue := takeCString(stack), takeCString(address)
	dnsValue, optionsValue := takeCString(dns), takeCString(options)
	bridgeMu.Lock()
	defer bridgeMu.Unlock()
	core.StopTun()
	releaseObject(tunCallback)
	tunCallback = nil
	if !core.StartTun(tunCallbacks{callback}, int(fd), stackValue, addressValue, dnsValue, optionsValue) {
		releaseObject(callback)
		return false
	}
	tunCallback = callback
	return true
}

//export quickSetup
func quickSetup(callback unsafe.Pointer, initParams, setupParams *C.char) {
	core.QuickSetup(takeCString(initParams), takeCString(setupParams), func(message string) {
		invokeResult(callback, message)
		releaseObject(callback)
	})
}

//export setEventListener
func setEventListener(callback unsafe.Pointer) {
	bridgeMu.Lock()
	defer bridgeMu.Unlock()
	core.SetEventListener(nil)
	releaseObject(listenerCallback)
	listenerCallback = callback
	if callback != nil {
		core.SetEventListener(func(data []byte) {
			invokeResult(callback, string(data))
		})
	}
}

//export stopTun
func stopTun() {
	bridgeMu.Lock()
	defer bridgeMu.Unlock()
	core.StopTun()
	releaseObject(tunCallback)
	tunCallback = nil
}

//export getTraffic
func getTraffic(onlyProxy bool) *C.char {
	return C.CString(core.GetTraffic(onlyProxy))
}

//export getTotalTraffic
func getTotalTraffic(onlyProxy bool) *C.char {
	return C.CString(core.GetTotalTraffic(onlyProxy))
}

//export suspend
func suspend(value bool) {
	if value {
		tunnel.OnSuspend()
	} else {
		tunnel.OnRunning()
	}
}

//export forceGC
func forceGC() {
	core.ForceGC()
}

//export updateDns
func updateDns(value *C.char) {
	core.UpdateDns(takeCString(value))
}

func main() {}
