#+test
package youtube

import "core:encoding/json"
import "core:testing"

@(test)
account_photo_uses_the_largest_https_image_not_the_last_entry :: proc(t: ^testing.T) {
	value, error := json.parse(
		`{"accountName":{"simpleText":"Example"},"accountPhoto":{"thumbnails":[
		{"url":"https://images.example/large","width":216},
		{"url":"http://images.example/insecure","width":512},
		{"url":"https://images.example/small","width":32}
	]}}`,
	)
	if !testing.expect_value(t, error, .None) {return}
	defer json.destroy_value(value)
	name, photo: string
	defer {delete(name); delete(photo)}
	find_account(value, &name, &photo)
	testing.expect_value(t, photo, "https://images.example/large")
}
