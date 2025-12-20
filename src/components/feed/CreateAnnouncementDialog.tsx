import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useToast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { z } from "zod";

const announcementSchema = z.object({
    title: z.string().trim().min(1, 'Title cannot be empty').max(200, 'Title must be less than 200 characters'),
    content: z.string().trim().min(1, 'Content cannot be empty').max(2000, 'Content must be less than 2000 characters')
});

interface CreateAnnouncementDialogProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    onAnnouncementCreated: () => void;
}

export function CreateAnnouncementDialog({
    open,
    onOpenChange,
    onAnnouncementCreated
}: CreateAnnouncementDialogProps) {
    const [newTitle, setNewTitle] = useState("");
    const [newContent, setNewContent] = useState("");
    const { toast } = useToast();

    const createAnnouncement = async () => {
        try {
            const validation = announcementSchema.safeParse({
                title: newTitle,
                content: newContent
            });

            if (!validation.success) {
                toast({
                    title: "Validation error",
                    description: validation.error.issues[0].message,
                    variant: "destructive",
                });
                return;
            }

            const { data: { user } } = await supabase.auth.getUser();
            if (!user) {
                toast({
                    title: "Authentication required",
                    description: "Please log in to post announcements",
                    variant: "destructive",
                });
                return;
            }

            const { error } = await supabase
                .from('announcements')
                .insert([
                    {
                        title: validation.data.title,
                        content: validation.data.content,
                        author_id: user.id,
                    }
                ]);

            if (error) throw error;

            setNewTitle("");
            setNewContent("");
            onOpenChange(false);
            onAnnouncementCreated();
            toast({
                title: "Success",
                description: "Announcement posted successfully!",
            });
        } catch (error) {
            console.error('Error creating announcement:', error);
            toast({
                title: "Error",
                description: "Failed to post announcement",
                variant: "destructive",
            });
        }
    };

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent className="bg-card border-border">
                <DialogHeader>
                    <DialogTitle className="text-foreground">Post Announcement</DialogTitle>
                </DialogHeader>
                <div className="space-y-4">
                    <Input
                        placeholder="Title"
                        value={newTitle}
                        onChange={(e) => setNewTitle(e.target.value)}
                        className="bg-background border-input text-foreground placeholder:text-muted-foreground"
                    />
                    <Textarea
                        placeholder="Content"
                        value={newContent}
                        onChange={(e) => setNewContent(e.target.value)}
                        className="bg-background border-input text-foreground placeholder:text-muted-foreground"
                    />
                    <div className="flex justify-end space-x-2">
                        <Button variant="outline" onClick={() => onOpenChange(false)}>
                            Cancel
                        </Button>
                        <Button
                            onClick={createAnnouncement}
                            className="bg-primary text-primary-foreground hover:bg-primary/90"
                        >
                            Post
                        </Button>
                    </div>
                </div>
            </DialogContent>
        </Dialog>
    );
}
