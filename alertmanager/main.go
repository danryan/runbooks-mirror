package main

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/google/go-jsonnet/ast"
	"github.com/google/go-jsonnet/parser"
)

func main() {
	log.SetFlags(0)
	if len(os.Args) != 2 {
		log.Fatalln("unexpected args, expected jdoc <PATH>")
	}

	path := os.Args[1]

	filepath.Walk(path, func(path string, info fs.FileInfo, err error) error {
		if info.IsDir() {
			return nil
		}
		log.Println(path)
		if err := parse(path); err != nil {
			return fmt.Errorf("failed to parse file at %s: %w", path, err)
		}
		return nil
	})
}

func parse(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		log.Fatalln(err)
	}
	tokens, err := parser.Lex(ast.DiagnosticFileName(path), "", string(data))
	if err != nil {
		log.Fatalln(err)
	}

	node, _, err := parser.Parse(tokens)
	if err != nil {
		log.Fatalln(err)
	}

	interpreter := Interpreter{}
	if err := interpreter.Interpret(node); err != nil {
		log.Fatalln(err)
	}

	data, err = json.Marshal(interpreter)
	if err != nil {
		log.Fatalln(err)
	}
	fmt.Println(string(data))

	return nil
}

type Interpreter struct {
	Comments   string
	Properties []Property
}

func (i *Interpreter) Interpret(node ast.Node) error {
	switch n := node.(type) {
	case *ast.Apply:
		log.Println("no root object found")
		return nil

	case *ast.Local:
		return i.Interpret(n.Body)

	case *ast.Object:
		comments := strings.Builder{}
		for _, fo := range *n.OpenFodder() {
			for _, c := range fo.Comment {
				comments.WriteString(c)
				comments.WriteString("\n")
			}
		}
		i.Comments = comments.String()
		comments.Reset()

		for _, fi := range n.Fields {
			for _, fo := range fi.Fodder1 {
				for _, c := range fo.Comment {
					comments.WriteString(c)
					comments.WriteString("\n")
				}
			}
			i.Properties = append(i.Properties, Property{
				Key:      string(*fi.Id),
				Comments: comments.String(),
			})
			comments.Reset()
		}

		return nil

	default:
		return fmt.Errorf("unable to evaluate unknown ast type: %s", reflect.TypeOf(n))
	}
}

type Property struct {
	Key      string
	Comments string
}
